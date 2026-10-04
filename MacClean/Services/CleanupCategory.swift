import Foundation

protocol CleanupCategory: Sendable {
    var type: CleanupCategoryType { get }
    var name: String { get }
    var description: String { get }
    var requiresAdmin: Bool { get }
    
    func scan() async throws -> CleanupScanResult
    func scanDetailed() async throws -> [CleanupFile]
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult
    func clean(moveToTrash: Bool, files: [CleanupFile]?, protectedPaths: [String]) async throws -> CleanupResult
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
    
    func scanDetailed() async throws -> [CleanupFile] {
        let scanResult = try await scan()
        return await CleanupCategoryDefaults.scanFiles(in: scanResult.paths)
    }
    
    func clean(moveToTrash: Bool, files: [CleanupFile]?, protectedPaths: [String]) async throws -> CleanupResult {
        if let files = files {
            let startTime = Date()
            let fileManager = FileManager.default
            let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteFiles(files, category: name, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
            
            return CleanupResult(
                category: type,
                success: true,
                itemsDeleted: itemsDeleted,
                spaceFreed: spaceFreed,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        // Default implementation ignores files and calls standard clean
        // This ensures backward compatibility until individual categories are updated
        return try await clean(moveToTrash: moveToTrash, protectedPaths: protectedPaths)
    }
}

enum CleanupCategoryDefaults {
    /// Lists the regular files under the given folders off the main thread.
    static func scanFiles(in urls: [URL]) async -> [CleanupFile] {
        await Task.detached(priority: .userInitiated) {
            urls.flatMap { FileScanner.scanFilesSync(at: $0) }
        }.value
    }
}
