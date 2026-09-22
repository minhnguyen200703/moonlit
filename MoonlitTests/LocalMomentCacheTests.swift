import XCTest
@testable import Moonlit

final class LocalMomentCacheTests: XCTestCase {
    func testDraftSurvivesReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LocalMomentCache(rootURL: root)
        _ = try await cache.load()
        let id = UUID()
        _ = try await cache.saveDraft(id: id, imageData: Data([1, 2, 3]), note: "hello", userID: nil, coupleID: nil)

        let reloaded = try await LocalMomentCache(rootURL: root).load()
        XCTAssertEqual(reloaded.map(\.id), [id])
        XCTAssertEqual(reloaded.first?.deliveryState, .queued)
    }

    func testUnreadableMetadataIsQuarantinedAndNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadata = root.appendingPathComponent("moment-cache-v2.json")
        try Data("not-json".utf8).write(to: metadata)

        do {
            _ = try await LocalMomentCache(rootURL: root).load()
            XCTFail("Expected corrupt metadata to fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: metadata), Data("not-json".utf8))
            let quarantined = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix("moment-cache-v2-corrupt-") }
            XCTAssertEqual(quarantined.count, 1)
        }
    }

    func testInterruptedUploadRemainsPendingAfterReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LocalMomentCache(rootURL: root)
        _ = try await cache.load()
        var draft = try await cache.saveDraft(
            id: UUID(),
            imageData: Data([1, 2, 3]),
            note: "resume me",
            userID: UUID(),
            coupleID: UUID()
        )
        draft.deliveryState = .uploading
        _ = try await cache.update(draft)

        let reloaded = LocalMomentCache(rootURL: root)
        _ = try await reloaded.load()
        let pending = await reloaded.pendingMoments()

        XCTAssertEqual(pending.map(\.id), [draft.id])
    }

    func testLegacyMomentsRequireExplicitAdoption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LocalMomentCache(rootURL: root)
        _ = try await cache.load()
        let draft = try await cache.saveDraft(
            id: UUID(),
            imageData: Data([1, 2, 3]),
            note: "private until shared",
            userID: nil,
            coupleID: nil
        )
        let userID = UUID()
        let coupleID = UUID()

        let adopted = try await cache.adoptLegacyMoments(userID: userID, coupleID: coupleID)

        XCTAssertEqual(adopted.map(\.id), [draft.id])
        XCTAssertEqual(adopted.first?.authorID, userID)
        XCTAssertEqual(adopted.first?.coupleID, coupleID)
        XCTAssertEqual(adopted.first?.deliveryState, .queued)
    }
}
