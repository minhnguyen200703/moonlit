import Foundation

actor LocalMomentCache {
    private struct Envelope: Codable {
        let version: Int
        var moments: [Moment]
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataURL: URL
    private let legacyMetadataURL: URL
    private let imagesDirectory: URL
    private var moments: [Moment] = []

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        let resolvedRoot = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = resolvedRoot
        metadataURL = resolvedRoot.appendingPathComponent("moment-cache-v2.json")
        legacyMetadataURL = resolvedRoot.appendingPathComponent("moments.json")
        imagesDirectory = resolvedRoot.appendingPathComponent("MoonlitImages", isDirectory: true)
    }

    func load() throws -> [Moment] {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.version == 2 else { throw LocalCacheError.unsupportedVersion }
                moments = envelope.moments.sorted { $0.capturedAt > $1.capturedAt }
                return moments
            } catch {
                let quarantine = rootURL.appendingPathComponent("moment-cache-v2-corrupt-\(UUID().uuidString).json")
                try? fileManager.copyItem(at: metadataURL, to: quarantine)
                throw LocalCacheError.unreadableMetadata(quarantine)
            }
        }

        if fileManager.fileExists(atPath: legacyMetadataURL.path) {
            do {
                let data = try Data(contentsOf: legacyMetadataURL)
                let legacy = try JSONDecoder().decode([LegacyMoment].self, from: data)
                moments = legacy.map {
                    Moment(
                        id: $0.id,
                        capturedAt: $0.createdAt,
                        createdAt: $0.createdAt,
                        note: $0.note,
                        localImageFileName: $0.imageFileName,
                        deliveryState: .queued,
                        reaction: $0.reaction,
                        createdByCurrentUser: true
                    )
                }.sorted { $0.capturedAt > $1.capturedAt }
                try persist(moments)
                return moments
            } catch {
                let quarantine = rootURL.appendingPathComponent("moments-v1-corrupt-\(UUID().uuidString).json")
                try? fileManager.copyItem(at: legacyMetadataURL, to: quarantine)
                throw LocalCacheError.unreadableMetadata(quarantine)
            }
        }

        moments = []
        return []
    }

    func saveDraft(id: UUID, imageData: Data, note: String, userID: UUID?, coupleID: UUID?) throws -> Moment {
        let fileName = "\(id.uuidString.lowercased()).jpg"
        let imageURL = imagesDirectory.appendingPathComponent(fileName)
        try imageData.write(to: imageURL, options: .atomic)

        let moment = Moment(
            id: id,
            coupleID: coupleID,
            authorID: userID,
            note: note,
            localImageFileName: fileName,
            deliveryState: .queued,
            createdByCurrentUser: true
        )
        let candidate = ([moment] + moments.filter { $0.id != id }).sorted { $0.capturedAt > $1.capturedAt }
        do {
            try persist(candidate)
            moments = candidate
            return moment
        } catch {
            try? fileManager.removeItem(at: imageURL)
            throw error
        }
    }

    func replace(with remote: [Moment], for userID: UUID, in coupleID: UUID) throws -> [Moment] {
        let localByID = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        let mergedRemote = remote.map { remoteMoment in
            guard let local = localByID[remoteMoment.id],
                  let localImageFileName = local.localImageFileName else {
                return remoteMoment
            }
            return Moment(
                id: remoteMoment.id,
                coupleID: remoteMoment.coupleID,
                authorID: remoteMoment.authorID,
                capturedAt: remoteMoment.capturedAt,
                createdAt: remoteMoment.createdAt,
                note: remoteMoment.note,
                storagePath: remoteMoment.storagePath,
                localImageFileName: localImageFileName,
                deliveryState: remoteMoment.deliveryState,
                reaction: remoteMoment.reaction,
                currentUserReacted: remoteMoment.currentUserReacted,
                reactionCount: remoteMoment.reactionCount,
                createdByCurrentUser: remoteMoment.createdByCurrentUser
            )
        }
        let remoteIDs = Set(remote.map(\.id))
        let pending = moments.filter {
            $0.deliveryState != .synced && !remoteIDs.contains($0.id)
                && ($0.coupleID == nil || ($0.coupleID == coupleID && $0.authorID == userID))
        }
        let otherIdentity = moments.filter {
            $0.coupleID != nil && !remoteIDs.contains($0.id)
                && ($0.coupleID != coupleID ||
                    ($0.authorID != userID && $0.deliveryState != .synced))
        }
        let candidate = (mergedRemote + pending + otherIdentity).sorted { $0.capturedAt > $1.capturedAt }
        try persist(candidate)
        moments = candidate
        return visibleMoments(for: userID, in: coupleID)
    }

    func update(_ updated: Moment) throws -> [Moment] {
        let candidate = ([updated] + moments.filter { $0.id != updated.id }).sorted { $0.capturedAt > $1.capturedAt }
        try persist(candidate)
        moments = candidate
        return candidate
    }

    func pendingMoments(for userID: UUID, in coupleID: UUID) -> [Moment] {
        moments.filter {
            ($0.deliveryState == .queued || $0.deliveryState == .uploading || $0.deliveryState == .failed)
                && $0.authorID == userID && $0.coupleID == coupleID
        }
    }

    func visibleMoments(for userID: UUID, in coupleID: UUID) -> [Moment] {
        moments.filter {
            $0.coupleID == nil || ($0.coupleID == coupleID &&
                ($0.deliveryState == .synced || $0.authorID == userID))
        }
    }

    func adoptLegacyMoments(userID: UUID, coupleID: UUID) throws -> [Moment] {
        let adopted = moments.filter { $0.coupleID == nil }.map { moment in
            Moment(
                id: moment.id,
                coupleID: coupleID,
                authorID: userID,
                capturedAt: moment.capturedAt,
                createdAt: moment.createdAt,
                note: moment.note,
                storagePath: moment.storagePath,
                localImageFileName: moment.localImageFileName,
                deliveryState: .queued,
                reaction: moment.reaction,
                currentUserReacted: moment.currentUserReacted,
                reactionCount: moment.reactionCount,
                createdByCurrentUser: true
            )
        }
        guard !adopted.isEmpty else { return [] }
        let adoptedIDs = Set(adopted.map(\.id))
        let candidate = (adopted + moments.filter { !adoptedIDs.contains($0.id) })
            .sorted { $0.capturedAt > $1.capturedAt }
        try persist(candidate)
        moments = candidate
        return adopted
    }

    func imageData(for moment: Moment) throws -> Data? {
        guard let fileName = moment.localImageFileName else { return nil }
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func cacheRemoteImage(_ data: Data, for momentID: UUID) throws -> String {
        let fileName = "remote-\(momentID.uuidString.lowercased()).jpg"
        try data.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    func remoteImageData(for momentID: UUID) throws -> Data? {
        let fileName = "remote-\(momentID.uuidString.lowercased()).jpg"
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func persist(_ value: [Moment]) throws {
        let data = try JSONEncoder().encode(Envelope(version: 2, moments: value))
        try data.write(to: metadataURL, options: .atomic)
    }
}

enum LocalCacheError: LocalizedError {
    case unsupportedVersion
    case unreadableMetadata(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This Moonlit diary was created by a newer app version."
        case .unreadableMetadata(let backup):
            return "Moonlit preserved unreadable diary data at \(backup.lastPathComponent). It will not be overwritten."
        }
    }
}
