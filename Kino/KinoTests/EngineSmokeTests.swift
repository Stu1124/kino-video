import XCTest
import KinoEngine
@testable import Kino

final class EngineSmokeTests: XCTestCase {
    func testEngineTimeWorksFromAppTarget() {
        let t = KTime(seconds: 3.0)
        XCTAssertEqual(Rational.fps24.frames(in: t), 72)
    }

    func testProjectRoundTrip() throws {
        var p = KinoProject()
        p.meta.name = "Smoke"
        let data = try p.encodedJSON()
        let decoded = try KinoProject.decode(data)
        XCTAssertEqual(decoded.meta.name, "Smoke")
        XCTAssertEqual(decoded.tracks.count, 1)
    }
}
