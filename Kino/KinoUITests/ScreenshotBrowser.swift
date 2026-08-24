import XCTest

/// Screenshot driver: launches Kino with synthesized fixture media, walks the
/// main flows and exports `.png` attachments that CI harvests for visual review.
final class ScreenshotBrowser: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--uitest", "--fixtures", "--demoproject"]
        app.launch()
    }

    func snap(_ name: String, _ element: XCUIElement? = nil) {
        let shot = element != nil ? element!.screenshot() : app.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testWalkHomeAndEditor() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        sleep(2)

        if app.staticTexts["Kino"].waitForExistence(timeout: 4) {
            snap("00-home-top")
        }

        // Open sample project if present
        let sample = app.staticTexts["Sample Edit"]
        if sample.waitForExistence(timeout: 3) {
            snap("01-home-with-sample")
            sample.tap()
            sleep(6) // editor boots + preview composites first frames
            snap("02-editor-default")
            // ruler scrub
            let ruler = app.otherElements["timeline-ui"]
            if ruler.exists {
                ruler.swipeRight()
                sleep(1)
                snap("03-after-scroll")
            }
        } else {
            snap("01-home-empty")
        }
    }
}
