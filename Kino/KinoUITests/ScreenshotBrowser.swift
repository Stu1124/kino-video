import XCTest

/// Screenshot driver: launches Kino, walks the main flows and exports
/// `.png` attachments that CI harvests as artifacts for visual review.
final class ScreenshotBrowser: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--uitest"]
        app.launchOptions = [:]
        app.launch()
    }

    func snap(_ name: String, _ element: XCUIElement? = nil) {
        let shot = element != nil ? element!.screenshot() : app.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testSmokeArchiveHome() {
        // Root boots into app (splash -> home placeholder for now)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        sleep(1)
        snap("00-splash-or-home")
        // No crash within 3s of idle
        sleep(2)
        XCTAssertTrue(app.state == .runningForeground)
    }
}
