import XCTest
@testable import Moonlit

final class MoonPhaseTests: XCTestCase {
    func testKnownReferenceNewMoon() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-01-06T18:14:00Z"))
        let phase = MoonPhase.current(on: date)
        XCTAssertEqual(phase.name, "New moon")
        XCTAssertLessThanOrEqual(phase.illumination, 1)
    }
}
