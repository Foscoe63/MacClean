#if canImport(XCTest)
import XCTest

@MainActor
final class CleanupEngineTests: XCTestCase {
    var cleanupEngine: CleanupEngine!
    
    override func setUp() {
        super.setUp()
        cleanupEngine = CleanupEngine()
    }
    
    override func tearDown() {
        cleanupEngine = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertFalse(cleanupEngine.isCleaning)
        XCTAssertEqual(cleanupEngine.currentProgress, 0.0)
        XCTAssertTrue(cleanupEngine.results.isEmpty)
        XCTAssertNil(cleanupEngine.summary)
    }
    
    func testScanCategories() async {
        let categories: Set<CleanupCategoryType> = [.userCaches, .trash]
        let items = await cleanupEngine.scanCategories(categories)
        
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { categories.contains($0.category) })
    }
    
    func testReset() {
        cleanupEngine.isCleaning = true
        cleanupEngine.currentProgress = 0.5
        cleanupEngine.currentStatus = "Testing"
        
        cleanupEngine.reset()
        
        XCTAssertFalse(cleanupEngine.isCleaning)
        XCTAssertEqual(cleanupEngine.currentProgress, 0.0)
        XCTAssertEqual(cleanupEngine.currentStatus, "")
        XCTAssertTrue(cleanupEngine.results.isEmpty)
        XCTAssertNil(cleanupEngine.summary)
    }
}
#endif

