import XCTest

/// End-to-end walkthrough. Runs against an iPhone 16 Pro simulator with
/// synthesized fixture media; each step grabs a .png so CI artifacts can be
/// reviewed visually.
final class ScreenshotBrowser: XCTestCase {

    let app = XCUIApplication()
    var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--uitest", "--fixtures", "--demoproject"]
        app.launch()
    }

    func snap(_ name: String, _ element: XCUIElement? = nil) {
        let shot = element != nil ? element!.screenshot() : app.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = String(format: "%02d-%@", step, name)
        att.lifetime = .keepAlways
        add(att)
        step += 1
    }

    func testFullWalkthrough() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(1)
        snap("home-boot")

        // Wait for fixture sample project to appear on home
        let sample = app.staticTexts["Sample Edit"]
        let deadline = Date().addingTimeInterval(90)
        while !sample.exists && Date() < deadline {
            sleep(2)
        }
        XCTAssertTrue(sample.exists, "Sample project should exist after fixture generation")
        snap("home-with-sample")
        sample.tap()

        // Editor boots; preview composites
        sleep(5)
        snap("editor-after-tap")
        if !app.buttons["export-button"].waitForExistence(timeout: 15) {
            let tree = app.debugDescription
            let att = XCTAttachment(string: tree)
            att.name = "editor-accessibility-tree"
            att.lifetime = .keepAlways
            add(att)
            XCTFail("export-button missing; tree captured")
            return
        }
        snap("editor-default")

        // Timeline exists: scrub a bit
        let timeline = app.otherElements["timeline-ui"]
        if timeline.exists {
            timeline.swipeRight()
        }
        sleep(1)
        snap("editor-scrolled")

        // Transport: play a moment
        app.swipeDown(velocity: .slow)

        // Export a real render
        let exportButton = app.buttons["export-button"]
        exportButton.tap()
        sleep(2)
        snap("export-pre")

        // Cancel quickly (rendering check happens in later iteration)
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
        }
        sleep(1)
        snap("back-to-editor")
    }
}
