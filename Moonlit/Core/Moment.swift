import Foundation

enum MomentDeliveryState: String, Codable, Equatable {
    case queued
    case uploading
    case synced
    case failed
}

struct Moment: Identifiable, Codable, Equatable {
    let id: UUID
    let coupleID: UUID?
    let authorID: UUID?
    let capturedAt: Date
    let createdAt: Date
    let note: String
    let storagePath: String?
    let localImageFileName: String?
    var deliveryState: MomentDeliveryState
    var reaction: String?
    var currentUserReacted: Bool?
    var reactionCount: Int?
    var createdByCurrentUser: Bool = false

    init(
        id: UUID = UUID(),
        coupleID: UUID? = nil,
        authorID: UUID? = nil,
        capturedAt: Date = .now,
        createdAt: Date = .now,
        note: String,
        storagePath: String? = nil,
        localImageFileName: String? = nil,
        deliveryState: MomentDeliveryState = .queued,
        reaction: String? = nil,
        currentUserReacted: Bool? = nil,
        reactionCount: Int? = nil,
        createdByCurrentUser: Bool = false
    ) {
        self.id = id
        self.coupleID = coupleID
        self.authorID = authorID
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.note = note
        self.storagePath = storagePath
        self.localImageFileName = localImageFileName
        self.deliveryState = deliveryState
        self.reaction = reaction
        self.currentUserReacted = currentUserReacted
        self.reactionCount = reactionCount
        self.createdByCurrentUser = createdByCurrentUser
    }
}

struct LegacyMoment: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let senderName: String
    let note: String
    let imageFileName: String
    var reaction: String?
}

struct Reply: Identifiable, Equatable {
    let id: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date
    let createdByCurrentUser: Bool
}

struct CoupleContext: Equatable {
    enum Status: String, Equatable {
        case waiting
        case active
    }

    let id: UUID
    let status: Status
    let currentUserID: UUID
    let memberCount: Int

    var isActive: Bool { status == .active && memberCount == 2 }
}

struct PairingInvitation: Equatable {
    let code: String
    let expiresAt: Date
}
