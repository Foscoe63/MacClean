import Foundation

struct CleanupResult: Identifiable {
    let id: UUID
    let category: CleanupCategoryType
    let success: Bool
    let itemsDeleted: Int
    let spaceFreed: Int64 // in bytes
    let error: CleanupError?
    let duration: TimeInterval
    /// True when the items went to the Trash, so `spaceFreed` is only reclaimed once the Trash is emptied.
    var movedToTrash: Bool = false
    
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
    /// Space actually reclaimed by permanent deletion.
    let totalSpaceFreed: Int64
    /// Space moved to the Trash; reclaimed only once the Trash is emptied.
    let totalSpaceMovedToTrash: Int64
    let successfulCategories: Int
    let failedCategories: Int
    let wasCancelled: Bool
    let results: [CleanupResult]
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceFreed, countStyle: .file)
    }
    
    var formattedSpaceMovedToTrash: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceMovedToTrash, countStyle: .file)
    }
}

nonisolated enum CleanupError: LocalizedError {
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
            return "Administrator authorization was cancelled or denied, so system caches and logs were not cleaned."
        case .invalidPath:
            return "Invalid file path."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

