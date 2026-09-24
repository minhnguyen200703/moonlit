import SwiftUI
import UIKit

@MainActor
final class MomentStore: ObservableObject {
    enum AppState: Equatable {
        case idle
        case loading
        case needsConfiguration(String)
        case pairing
        case ready
        case failed(String)
    }

    @Published private(set) var appState: AppState = .idle
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var couple: CoupleContext?
    @Published private(set) var invitation: PairingInvitation?
    @Published private(set) var isPairing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastRefreshSucceeded = false
    @Published private(set) var legacyImportCount = 0
    @Published private(set) var syncRevision = 0
    @Published var transientError: String?

    private let localCache: LocalMomentCache
    private let imageCache = NSCache<NSUUID, UIImage>()
    private var gateway: SupabaseGateway?
    private var currentUserID: UUID?
    private var hasStarted = false
    private var activeUploads: Set<UUID> = []
    private var refreshQueued = false

    init(localCache: LocalMomentCache = LocalMomentCache()) {
        self.localCache = localCache
    }

    var latestMoment: Moment? { moments.first }

    func start(force: Bool = false) async {
        guard force || !hasStarted else { return }
        hasStarted = true
        appState = .loading
        lastRefreshSucceeded = false
        do {
            await gateway?.stopRealtime()
            moments = try await localCache.load()
            updateLegacyImportCount()
            let configuration = try AppConfiguration.load()
            let gateway = SupabaseGateway(configuration: configuration)
            self.gateway = gateway
            let userID = try await gateway.ensureSession()
            if currentUserID != userID {
                imageCache.removeAllObjects()
                invitation = nil
            }
            currentUserID = userID
            try await reloadCouple(userID: userID)
        } catch let error as ConfigurationError {
            appState = .needsConfiguration(error.localizedDescription)
        } catch {
            appState = .failed(error.localizedDescription)
        }
    }

    func retryBootstrap() async {
        hasStarted = false
        await start(force: true)
    }

    func createInvitation(displayName: String) async {
        guard let gateway else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count) else {
            transientError = "Enter a name between 1 and 40 characters."
            return
        }
        isPairing = true
        defer { isPairing = false }
        do {
            invitation = try await gateway.createInvitation(displayName: name)
            if let currentUserID { try await reloadCouple(userID: currentUserID) }
        } catch {
            transientError = error.localizedDescription
        }
    }

    func join(code: String, displayName: String) async {
        guard let gateway else { return }
        let normalizedCode = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCode.count == 12 else {
            transientError = "Invitation codes contain 12 letters and numbers."
            return
        }
        guard (1...40).contains(name.count) else {
            transientError = "Enter a name between 1 and 40 characters."
            return
        }
        isPairing = true
        defer { isPairing = false }
        do {
            try await gateway.join(code: normalizedCode, displayName: name)
            invitation = nil
            if let currentUserID { try await reloadCouple(userID: currentUserID) }
        } catch {
            transientError = "That code is invalid, expired, or already used."
        }
    }

    func checkPairing() async {
        guard appState == .pairing, let currentUserID else { return }
        do { try await reloadCouple(userID: currentUserID) }
        catch { /* A later poll or manual retry can recover. */ }
    }

    func add(image: UIImage, note: String) async throws {
        guard let currentUserID, let couple, couple.isActive else {
            throw MomentStoreError.notPaired
        }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else { throw MomentStoreError.noteTooLong }
        let id = UUID()
        let data = try await ImagePipeline.prepareJPEG(image)
        let draft = try await localCache.saveDraft(
            id: id,
            imageData: data,
            note: cleanNote,
            userID: currentUserID,
            coupleID: couple.id
        )
        moments.insert(draft, at: 0)
        await upload(draft)
    }

    func retry(moment: Moment) async {
        await upload(moment)
    }

    func shareLegacyMoments() async {
        guard let currentUserID, let couple, couple.isActive else {
            transientError = MomentStoreError.notPaired.localizedDescription
            return
        }
        do {
            let adopted = try await localCache.adoptLegacyMoments(userID: currentUserID, coupleID: couple.id)
            moments = await localCache.visibleMoments(for: currentUserID, in: couple.id)
            updateLegacyImportCount()
            for moment in adopted { await upload(moment) }
        } catch {
            transientError = "Moonlit could not prepare your earlier moments for sharing."
        }
    }

    func image(for moment: Moment) async -> UIImage? {
        guard moments.contains(where: { $0.id == moment.id }) else { return nil }
        if let cached = imageCache.object(forKey: moment.id as NSUUID) { return cached }
        do {
            if let data = try await localCache.imageData(for: moment), let image = UIImage(data: data) {
                imageCache.setObject(image, forKey: moment.id as NSUUID)
                return image
            }
            if let data = try await localCache.remoteImageData(for: moment.id), let image = UIImage(data: data) {
                imageCache.setObject(image, forKey: moment.id as NSUUID)
                return image
            }
            guard let path = moment.storagePath, let gateway else { return nil }
            let data = try await gateway.downloadImage(path: path)
            guard let image = UIImage(data: data) else { return nil }
            imageCache.setObject(image, forKey: moment.id as NSUUID)
            _ = try? await localCache.cacheRemoteImage(data, for: moment.id)
            return image
        } catch {
            return nil
        }
    }

    func react(to momentID: UUID, with emoji: String = "♥︎") async {
        guard let gateway else { return }
        do {
            let currentUserReacted = moments.first(where: { $0.id == momentID })?.currentUserReacted ?? false
            try await gateway.setReaction(momentID: momentID, emoji: emoji, active: !currentUserReacted)
            await refreshMoments()
        } catch {
            transientError = "Your reaction could not be saved. Please try again."
        }
    }

    func replies(for momentID: UUID) async throws -> [Reply] {
        guard let gateway, let currentUserID else { return [] }
        return try await gateway.fetchReplies(momentID: momentID, currentUserID: currentUserID)
    }

    func sendReply(id: UUID, to momentID: UUID, body: String) async throws {
        guard let gateway else { throw MomentStoreError.notConfigured }
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2_000).contains(clean.count) else { throw MomentStoreError.invalidReply }
        try await gateway.createReply(id: id, momentID: momentID, body: clean)
    }

    func refreshMoments() async {
        guard let gateway, let couple, couple.isActive, let currentUserID else { return }
        if isSyncing {
            refreshQueued = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            refreshQueued = false
            do {
                let remote = try await gateway.fetchMoments(coupleID: couple.id, currentUserID: currentUserID)
                guard self.currentUserID == currentUserID, self.couple?.id == couple.id else { return }
                let refreshed = try await localCache.replace(with: remote, for: currentUserID, in: couple.id)
                guard self.currentUserID == currentUserID, self.couple?.id == couple.id else { return }
                moments = refreshed
                updateLegacyImportCount()
                lastRefreshSucceeded = true
                syncRevision &+= 1
            } catch {
                lastRefreshSucceeded = false
                transientError = "Moonlit could not refresh your shared sky."
            }
        } while refreshQueued
    }

    private func reloadCouple(userID: UUID) async throws {
        guard let gateway else { throw MomentStoreError.notConfigured }
        couple = try await gateway.fetchCouple(for: userID)
        if let couple {
            moments = await localCache.visibleMoments(for: userID, in: couple.id)
        } else {
            moments = []
        }
        updateLegacyImportCount()
        guard let couple else {
            appState = .pairing
            return
        }
        guard couple.isActive else {
            appState = .pairing
            return
        }
        appState = .ready
        do {
            try await gateway.startRealtime(coupleID: couple.id) { [weak self] in
                await self?.refreshMoments()
            }
        } catch {
            transientError = "Live updates are temporarily unavailable. Pull to refresh while Moonlit reconnects."
        }
        await refreshMoments()
        await resumePendingUploads()
    }

    func resumePendingUploads() async {
        guard let currentUserID, let couple, couple.isActive else { return }
        if let gateway, !gateway.hasRealtimeSubscription {
            do {
                try await gateway.startRealtime(coupleID: couple.id) { [weak self] in
                    await self?.refreshMoments()
                }
            } catch {
                transientError = "Live updates are temporarily unavailable. Pull to refresh while Moonlit reconnects."
            }
        }
        let pending = await localCache.pendingMoments(for: currentUserID, in: couple.id)
        for moment in pending { await upload(moment) }
    }

    private func upload(_ moment: Moment) async {
        guard let gateway, let currentUserID, let couple, couple.isActive,
              moment.authorID == currentUserID, moment.coupleID == couple.id else {
            transientError = "This moment belongs to another Moonlit session and will stay on this iPhone."
            return
        }
        guard activeUploads.insert(moment.id).inserted else { return }
        defer { activeUploads.remove(moment.id) }
        do {
            guard let data = try await localCache.imageData(for: moment) else {
                throw MomentStoreError.missingImage
            }
            var uploading = moment
            uploading.deliveryState = .uploading
            _ = try await localCache.update(uploading)
            moments = await localCache.visibleMoments(for: currentUserID, in: couple.id)
            try await gateway.upload(moment: uploading, imageData: data)
            guard self.currentUserID == currentUserID, self.couple?.id == couple.id else { return }
            var synced = uploading
            synced.deliveryState = .synced
            _ = try await localCache.update(synced)
            moments = await localCache.visibleMoments(for: currentUserID, in: couple.id)
            updateLegacyImportCount()
            await refreshMoments()
        } catch {
            var failed = moment
            failed.deliveryState = .failed
            if (try? await localCache.update(failed)) != nil {
                moments = await localCache.visibleMoments(for: currentUserID, in: couple.id)
            }
            transientError = "This moment is saved on this iPhone. Moonlit will retry when you return, or you can tap Retry."
        }
    }

    private func updateLegacyImportCount() {
        legacyImportCount = moments.filter { $0.coupleID == nil }.count
    }
}

enum MomentStoreError: LocalizedError {
    case notPaired
    case notConfigured
    case noteTooLong
    case invalidReply
    case missingImage

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Pair with your person before sharing a moment."
        case .notConfigured: return "Moonlit is not connected to Supabase yet."
        case .noteTooLong: return "Moon Notes can contain up to 500 characters."
        case .invalidReply: return "Replies must contain between 1 and 2,000 characters."
        case .missingImage: return "The local photo file is missing."
        }
    }
}
