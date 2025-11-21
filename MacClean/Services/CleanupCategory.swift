import Foundation

protocol CleanupCategory {
    var type: CleanupCategoryType { get }
    var name: String { get }
    var description: String { get }
    var requiresAdmin: Bool { get }
    
    func scan() async throws -> CleanupScanResult
    func clean(moveToTrash: Bool) async throws -> CleanupResult
}

struct CleanupScanResult {
    let category: CleanupCategoryType
    let itemCount: Int
    let estimatedSize: Int64
    let paths: [URL]
}

extension CleanupCategory {
    var name: String {
        type.displayName
    }
    
    var description: String {
        type.description
    }
}

