import XCTest

final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws { XCUIApplication().terminate() }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["PORTFOLIO_UI_TEST"] = UUID().uuidString
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testArrivalPersistsAndProofIsRequired() {
    let app = launch()
    let stop = app.buttons.containing(.staticText, identifier: "North Beach Studio").firstMatch
    if stop.waitForExistence(timeout: 10) {
      stop.tap()
    } else {
      app.staticTexts["North Beach Studio"].tap()
    }
    app.swipeUp()
    XCTAssertTrue(app.buttons["Mark arrived"].waitForExistence(timeout: 5))
    app.buttons["Mark arrived"].tap()
    XCTAssertTrue(app.textFields["Recipient name"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Complete delivery"].isEnabled)
    capture(app, "proof-required")
    app.terminate()
    app.launch()
    app.staticTexts["North Beach Studio"].tap()
    app.swipeUp()
    XCTAssertTrue(app.textFields["Recipient name"].waitForExistence(timeout: 5))
  }
}
