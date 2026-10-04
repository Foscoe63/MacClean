import Foundation

/// Capacity of the volume that holds the user's home folder.
nonisolated struct DiskSpace: Sendable {
    let total: Int64
    /// Space available for new files, including purgeable space macOS frees on demand (matches Finder).
    let available: Int64
    
    var used: Int64 { max(0, total - available) }
    
    static func current() -> DiskSpace? {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return DiskSpace(total: Int64(total), available: available)
    }
}
