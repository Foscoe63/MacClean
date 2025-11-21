#if canImport(XCTest)
import XCTest

final class LMStudioServiceTests: XCTestCase {
    var service: LMStudioService!
    
    override func setUp() {
        super.setUp()
        service = LMStudioService(
            endpoint: "http://localhost:1234/v1",
            model: "test-model"
        )
    }
    
    func testServiceType() {
        XCTAssertEqual(service.serviceType, .lmStudio)
    }
    
    func testInitialization() {
        XCTAssertEqual(service.endpoint, "http://localhost:1234/v1")
        XCTAssertEqual(service.model, "test-model")
    }
    
    // Note: Integration tests would require a running LM Studio instance
    // These are unit tests for the service structure
}
#endif

