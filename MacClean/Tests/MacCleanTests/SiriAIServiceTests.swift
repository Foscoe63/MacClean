#if canImport(XCTest)
import XCTest

final class SiriAIServiceTests: XCTestCase {
    var service: SiriAIService!
    
    override func setUp() {
        super.setUp()
        service = SiriAIService()
    }
    
    func testServiceType() {
        XCTAssertEqual(service.serviceType, .siriAI)
    }
    
    func testGetSuggestions() async throws {
        let items = [
            CleanupItem(
                name: "Test Cache",
                description: "Test",
                category: .userCaches,
                estimatedSize: 100_000_000
            )
        ]
        
        let suggestions = try await service.getSuggestions(for: items)
        
        // SiriAIService should provide suggestions for large items
        XCTAssertFalse(suggestions.isEmpty)
    }
}
#endif

