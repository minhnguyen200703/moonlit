import Foundation
import Supabase

@MainActor
final class SupabaseGateway {
    private let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    var hasRealtimeSubscription: Bool { realtimeChannel != nil }

    init(configuration: AppConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.publishableKey
        )
    }

    func ensureSession() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch let error as AuthError where error == .sessionMissing {
            return try await client.auth.signInAnonymously().user.id
        }
    }

    func fetchCouple(for userID: UUID) async throws -> CoupleContext? {
        let members: [MemberDTO] = try await client
            .from("couple_members")
            .select()
            .execute()
            .value
        guard let own = members.first(where: { $0.userID == userID }) else { return nil }
        let couples: [CoupleDTO] = try await client
            .from("couples")
            .select()
            .eq("id", value: own.coupleID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let couple = couples.first, let status = CoupleContext.Status(rawValue: couple.status) else {
            return nil
        }
        return CoupleContext(id: own.coupleID, status: status, currentUserID: userID, memberCount: members.count)
    }

    func createInvitation(displayName: String) async throws -> PairingInvitation {
        let response: PairingResponseDTO = try await client.functions.invoke(
            "pairing",
            options: FunctionInvokeOptions(body: [
                "action": "create",
                "displayName": displayName
            ])
        )
        guard let code = response.code,
              let expires = response.expiresAt.flatMap(DateParser.date) else {
            throw GatewayError.invalidResponse
        }
        return PairingInvitation(code: code, expiresAt: expires)
    }

    func join(code: String, displayName: String) async throws {
        let _: PairingResponseDTO = try await client.functions.invoke(
            "pairing",
            options: FunctionInvokeOptions(body: [
                "action": "join",
                "code": code,
                "displayName": displayName
            ])
        )
    }

    func fetchMoments(coupleID: UUID, currentUserID: UUID) async throws -> [Moment] {
        let pageSize = 200
        var momentDTOs: [MomentDTO] = []
        var offset = 0
        while true {
            let page: [MomentDTO] = try await client
                .from("moments")
                .select()
                .eq("couple_id", value: coupleID.uuidString)
                .eq("upload_state", value: "ready")
                .order("captured_at", ascending: false)
                .order("id", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            momentDTOs.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        var reactions: [ReactionDTO] = []
        offset = 0
        while true {
            let page: [ReactionDTO] = try await client
                .from("reactions")
                .select()
                .eq("couple_id", value: coupleID.uuidString)
                .eq("is_active", value: true)
                .order("moment_id", ascending: true)
                .order("user_id", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            reactions.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        let reactionsByMoment = Dictionary(grouping: reactions, by: \.momentID)
        return momentDTOs.compactMap { dto in
            guard let capturedAt = DateParser.date(dto.capturedAt),
                  let createdAt = DateParser.date(dto.createdAt) else { return nil }
            let momentReactions = reactionsByMoment[dto.id] ?? []
            let ownReaction = momentReactions.first(where: { $0.userID == currentUserID })
            let reaction = momentReactions.first(where: { $0.userID != currentUserID })?.emoji
                ?? ownReaction?.emoji
            return Moment(
                id: dto.id,
                coupleID: dto.coupleID,
                authorID: dto.authorID,
                capturedAt: capturedAt,
                createdAt: createdAt,
                note: dto.note,
                storagePath: dto.storagePath,
                deliveryState: .synced,
                reaction: reaction,
                currentUserReacted: ownReaction != nil,
                reactionCount: momentReactions.count,
                createdByCurrentUser: dto.authorID == currentUserID
            )
        }
    }

    func upload(moment: Moment, imageData: Data) async throws {
        let capturedAt = DateParser.string(moment.capturedAt)
        let params = BeginMomentParams(pMomentID: moment.id, pNote: moment.note, pCapturedAt: capturedAt)
        let reserved: MomentDTO = try await client
            .rpc("begin_moment", params: params)
            .single()
            .execute()
            .value
        do {
            try await client.storage
                .from("moment-photos")
                .upload(
                    reserved.storagePath,
                    data: imageData,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
                )
        } catch {
            do {
                let _: MomentDTO = try await client
                    .rpc("finalize_moment", params: MomentIDParams(pMomentID: moment.id))
                    .single()
                    .execute()
                    .value
                return
            } catch {
                throw error
            }
        }
        let _: MomentDTO = try await client
            .rpc("finalize_moment", params: MomentIDParams(pMomentID: moment.id))
            .single()
            .execute()
            .value
    }

    func downloadImage(path: String) async throws -> Data {
        try await client.storage.from("moment-photos").download(path: path)
    }

    func setReaction(momentID: UUID, emoji: String?, active: Bool) async throws {
        let params = ReactionParams(pMomentID: momentID, pEmoji: emoji ?? "♡", pIsActive: active)
        let _: ReactionDTO = try await client
            .rpc("set_reaction", params: params)
            .single()
            .execute()
            .value
    }

    func fetchReplies(momentID: UUID, currentUserID: UUID) async throws -> [Reply] {
        let values: [ReplyDTO] = try await client
            .from("replies")
            .select()
            .eq("moment_id", value: momentID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return values.compactMap { value in
            guard let date = DateParser.date(value.createdAt) else { return nil }
            return Reply(
                id: value.id,
                authorID: value.authorID,
                body: value.body,
                createdAt: date,
                createdByCurrentUser: value.authorID == currentUserID
            )
        }
    }

    func createReply(id: UUID, momentID: UUID, body: String) async throws {
        let params = ReplyParams(pReplyID: id, pMomentID: momentID, pBody: body)
        let _: ReplyDTO = try await client
            .rpc("create_reply", params: params)
            .single()
            .execute()
            .value
    }

    func startRealtime(coupleID: UUID, onChange: @escaping @MainActor () async -> Void) async throws {
        await stopRealtime()
        let channel = client.channel("couple:\(coupleID.uuidString.lowercased())") { options in
            options.isPrivate = true
        }
        let stream = channel.broadcastStream(event: "diary_changed")
        do {
            try await channel.subscribeWithError()
        } catch {
            await client.removeChannel(channel)
            throw error
        }
        realtimeChannel = channel
        realtimeTask = Task { @MainActor in
            for await _ in stream {
                guard !Task.isCancelled else { break }
                await onChange()
            }
        }
    }

    func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }
}

private struct MemberDTO: Decodable {
    let coupleID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case userID = "user_id"
    }
}

private struct CoupleDTO: Decodable {
    let id: UUID
    let status: String
}

private struct MomentDTO: Decodable {
    let id: UUID
    let coupleID: UUID
    let authorID: UUID
    let note: String
    let storagePath: String
    let capturedAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, note
        case coupleID = "couple_id"
        case authorID = "author_id"
        case storagePath = "storage_path"
        case capturedAt = "captured_at"
        case createdAt = "created_at"
    }
}

private struct ReactionDTO: Decodable {
    let momentID: UUID
    let userID: UUID
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case emoji
        case momentID = "moment_id"
        case userID = "user_id"
    }
}

private struct ReplyDTO: Decodable {
    let id: UUID
    let authorID: UUID
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

private struct PairingResponseDTO: Decodable {
    let coupleId: UUID?
    let code: String?
    let expiresAt: String?
}

private struct BeginMomentParams: Encodable {
    let pMomentID: UUID
    let pNote: String
    let pCapturedAt: String

    enum CodingKeys: String, CodingKey {
        case pMomentID = "p_moment_id"
        case pNote = "p_note"
        case pCapturedAt = "p_captured_at"
    }
}

private struct MomentIDParams: Encodable {
    let pMomentID: UUID
    enum CodingKeys: String, CodingKey { case pMomentID = "p_moment_id" }
}

private struct ReactionParams: Encodable {
    let pMomentID: UUID
    let pEmoji: String
    let pIsActive: Bool
    enum CodingKeys: String, CodingKey {
        case pMomentID = "p_moment_id"
        case pEmoji = "p_emoji"
        case pIsActive = "p_is_active"
    }
}

private struct ReplyParams: Encodable {
    let pReplyID: UUID
    let pMomentID: UUID
    let pBody: String
    enum CodingKeys: String, CodingKey {
        case pReplyID = "p_reply_id"
        case pMomentID = "p_moment_id"
        case pBody = "p_body"
    }
}

private enum DateParser {
    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum GatewayError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Moonlit received an unexpected response. Please try again."
        }
    }
}
