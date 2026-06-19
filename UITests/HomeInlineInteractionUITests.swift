import XCTest

final class HomeInlineInteractionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeLaunchesWithQinglanTapTarget() throws {
        let app = makeLoggedInApp()

        XCTAssertTrue(app.buttons["home-qinglan-avatar-button"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["顺手处理"].exists)
        XCTAssertFalse(app.staticTexts["有什么需要我处理？"].exists)
        XCTAssertFalse(app.buttons["确认"].exists)
        XCTAssertFalse(app.buttons["取消"].exists)
    }

    func testHomeDoesNotShowScheduleEntryButtonOrTabBar() throws {
        let app = makeLoggedInApp()

        XCTAssertFalse(app.buttons["home-schedule-entry-button"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    private func makeLoggedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestLoggedIn")
        app.launch()
        return app
    }
}
