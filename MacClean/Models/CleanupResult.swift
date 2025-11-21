import Foundation

struct CleanupResult: Identifiable {
    let id: UUID
    let category: CleanupCategoryType
    let success: Bool
    let itemsDeleted: Int
    let spaceFreed: Int64 // in bytes
    let error: CleanupError?
    let duration: TimeInterval
    
    init(
        id: UUID = UUID(),
        category: CleanupCategoryType,
        success: Bool,
        itemsDeleted: Int = 0,
        spaceFreed: Int64 = 0,
        error: CleanupError? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.category = category
        self.success = success
        self.itemsDeleted = itemsDeleted
        self.spaceFreed = spaceFreed
        self.error = error
        self.duration = duration
    }
}

struct CleanupSummary {
    let totalItemsDeleted: Int
    let totalSpaceFreed: Int64
    let successfulCategories: Int
    let failedCategories: Int
    let results: [CleanupResult]
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceFreed, countStyle: .file)
    }
}

enum CleanupError: LocalizedError {
    case accessDenied
    case fileNotFound
    case deletionFailed(String)
    case authorizationFailed
    case invalidPath
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied. Please check permissions."
        case .fileNotFound:
            return "File or directory not found."
        case .deletionFailed(let reason):
            return "Deletion failed: \(reason)"
        case .authorizationFailed:
            return "System caches and logs require administrator privileges. Please run the app with admin rights or use Terminal: sudo rm -rf /Library/Caches/*"
        case .invalidPath:
            return "Invalid file path."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

