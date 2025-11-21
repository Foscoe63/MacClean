#if canImport(XCTest)
import XCTest

final class MacCleanUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testAppLaunch() throws {
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
    
    func testPreferencesWindow() throws {
        // Open preferences
        app.menuBars.menuBarItems["MacClean"].click()
        app.menuBars.menuItems["Preferences..."].click()
        
        // Check if preferences window appears
        let preferencesWindow = app.windows["Preferences"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 2))
    }
    
    func testScanButton() throws {
        let scanButton = app.buttons["Scan"]
        XCTAssertTrue(scanButton.exists)
        
        scanButton.click()
        
        // Wait for scan to complete (adjust timeout as needed)
        let progressIndicator = app.progressIndicators.firstMatch
        if progressIndicator.exists {
            XCTAssertTrue(progressIndicator.waitForDisappearance(timeout: 10))
        }
    }
}
#endif

