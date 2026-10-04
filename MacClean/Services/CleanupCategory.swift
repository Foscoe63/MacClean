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
        // Without a reviewed file list, clean the whole category
        guard let files else {
            return try await clean(moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        }
        
        let startTime = Date()
        let outcome = await BackgroundFileWork.deleteFiles(
            files,
            category: name,
            moveToTrash: moveToTrash,
            protectedPaths: protectedPaths
        )
        DeletionLogManager.shared.logDeletions(outcome.logEntries)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: outcome.itemsDeleted,
            spaceFreed: outcome.spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
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
