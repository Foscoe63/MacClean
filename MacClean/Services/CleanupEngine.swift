import Foundation
import SwiftUI

@Observable
class CleanupEngine {
    var isCleaning = false
    var currentProgress: Double = 0.0
    var currentStatus: String = ""
    var results: [CleanupResult] = []
    var summary: CleanupSummary?
    
    private let fileManager = FileManager.default
    let authorizationHelper = AuthorizationHelper()
    
    private var categories: [any CleanupCategory] = []
    
    init() {
        setupCategories()
    }
    
    private func setupCategories() {
        categories = [
            UserCachesCategory(),
            SystemCachesCategory(),
            UserLogsCategory(),
            SystemLogsCategory(),
            SafariCacheCategory(),
            ChromeCacheCategory(),
            FirefoxCacheCategory(),
            DownloadsCategory(),
            TrashCategory(),
            // Developer tools
            XcodeDerivedDataCategory(),
            XcodeArchivesCategory(),
            NPMCacheCategory(),
            CocoaPodsCacheCategory(),
            HomebrewCacheCategory(),
            // Docker
            DockerCacheCategory(),
            // More browsers
            EdgeCacheCategory(),
            BraveCacheCategory(),
            // Application-specific
            SpotifyCacheCategory(),
            SlackCacheCategory(),
            ZoomCacheCategory(),
            // System maintenance
            iOSBackupsCategory()
        ]
    }
    
    /// Scans the requested cleanup categories concurrently for better performance.
    /// Uses a task group to launch scans in parallel while preserving order‑independent results.
    func scanCategories(_ types: Set<CleanupCategoryType>) async -> [CleanupItem] {
        var items: [CleanupItem] = []

        await withTaskGroup(of: CleanupItem?.self) { group in
            for category in categories where types.contains(category.type) {
                // Capture static info on the main actor before entering background task
                let name = await MainActor.run { category.name }
                let description = await MainActor.run { category.description }
                let type = await MainActor.run { category.type }
                let requiresAdmin = await MainActor.run { category.requiresAdmin }

                group.addTask {
                    do {
                        let scanResult = try await category.scan()
                        // Construct CleanupItem on the main actor to satisfy isolation rules
                        return await MainActor.run {
                            CleanupItem(
                                name: name,
                                description: description,
                                category: type,
                                isEnabled: true,
                                requiresAdmin: requiresAdmin,
                                estimatedSize: scanResult.estimatedSize
                            )
                        }
                    } catch {
                        // Log and return nil so the group can continue
                        await MainActor.run {
                            print("Failed to scan \(name): \(error)")
                        }
                        return nil
                    }
                }
            }

            for await result in group {
                if let item = result {
                    items.append(item)
                }
            }
        }

        return items
    }
    
    func getDetailedFiles(for categoryType: CleanupCategoryType) async -> [CleanupFile] {
        guard let category = categories.first(where: { $0.type == categoryType }) else {
            return []
        }
        
        do {
            return try await category.scanDetailed()
        } catch {
            print("Failed to get detailed files for \(categoryType): \(error)")
            return []
        }
    }
    
    func cleanCategories(_ items: [CleanupItem], moveToTrash: Bool = true, protectedPaths: [String] = [], progressHandler: @escaping (Double, String) -> Void) async {
        isCleaning = true
        results = []
        currentProgress = 0.0
        currentStatus = ""
        
        let categoriesToClean = items.filter { $0.isEnabled }
        let totalCategories = Double(categoriesToClean.count)
        
        for (index, item) in categoriesToClean.enumerated() {
            guard let category = categories.first(where: { $0.type == item.category }) else { continue }
            
            let progress = Double(index) / totalCategories
            // Capture UI‑related strings on the main actor to avoid Sendable violations
            let categoryName = await MainActor.run { category.name }
            progressHandler(progress, "Cleaning \(categoryName)...")
            currentProgress = progress
            currentStatus = "Cleaning \(categoryName)..."
            
            do {
                var result: CleanupResult
                // For categories requiring admin, always use privileged cleaning method that triggers authorization dialog
                if category.requiresAdmin {
                    // This call triggers AuthorizationHelper dialog and privileged cleanup
                    // Note: Admin cleanup currently doesn't support individual file exclusions or protected paths
                    result = try await cleanWithAuthorization(category: category, moveToTrash: moveToTrash)
                } else {
                    // For non-admin categories, use regular clean method with files if available
                    result = try await category.clean(moveToTrash: moveToTrash, files: item.files, protectedPaths: protectedPaths)
                }
                results.append(result)
            } catch let error as CleanupError {
                let errorResult = CleanupResult(
                    category: category.type,
                    success: false,
                    error: error,
                    duration: 0
                )
                results.append(errorResult)
            } catch {
                let errorResult = CleanupResult(
                    category: category.type,
                    success: false,
                    error: .unknown(error),
                    duration: 0
                )
                results.append(errorResult)
            }
        }
        
        progressHandler(1.0, "Complete")
        currentProgress = 1.0
        currentStatus = "Complete"
        
        summary = createSummary()
        isCleaning = false
    }
    
    private func cleanWithAuthorization(category: any CleanupCategory, moveToTrash: Bool = true) async throws -> CleanupResult {
        let startTime = Date()
        
        let path: String
        switch category.type {
        case .systemCaches:
            path = "/Library/Caches"
        case .systemLogs:
            path = "/var/log"
        default:
            throw CleanupError.invalidPath
        }
        
        // The AppleScript below will trigger the standard macOS admin password prompt when needed
        // Exclude protected Apple system caches that can't be deleted even with admin
        // Use a simpler approach: delete all except protected ones, ignore errors for protected files
        let protected = "com.apple.amsengagementd.classicdatavault com.apple.aned com.apple.aneuserd"
        let script = "do shell script \"cd '\(path)' && for f in *; do if ! echo '\(protected)' | grep -q \\\"$f\\\"; then rm -rf \\\"$f\\\" 2>/dev/null || true; fi; done\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            // Read error output
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            
            // Check if it's just protected files that couldn't be deleted
            // If so, that's okay - we still succeeded in cleaning what we could
            if errorText.contains("Operation not permitted") {
                // Some protected files couldn't be deleted, but that's expected
                // Return success since we cleaned what we could
                return CleanupResult(
                    category: category.type,
                    success: true,
                    itemsDeleted: 0,
                    spaceFreed: 0,
                    duration: Date().timeIntervalSince(startTime)
                )
            }
            
            // Real error - throw it
            print("Cleanup failed: \(errorText)")
            throw CleanupError.deletionFailed("Some files could not be deleted: \(errorText)")
        }
        
        return CleanupResult(
            category: category.type,
            success: true,
            itemsDeleted: 0,
            spaceFreed: 0,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    private func createSummary() -> CleanupSummary {
        let totalItems = results.reduce(0) { $0 + $1.itemsDeleted }
        let totalSpace = results.reduce(0) { $0 + $1.spaceFreed }
        let successful = results.filter { $0.success }.count
        let failed = results.filter { !$0.success }.count
        
        return CleanupSummary(
            totalItemsDeleted: totalItems,
            totalSpaceFreed: totalSpace,
            successfulCategories: successful,
            failedCategories: failed,
            results: results
        )
    }
    
    func reset() {
        isCleaning = false
        currentProgress = 0.0
        currentStatus = ""
        results = []
        summary = nil
    }
    
}

// MARK: - Category Implementations

struct UserCachesCategory: CleanupCategory {
    let type: CleanupCategoryType = .userCaches
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let cachesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches")
        
        guard fileManager.fileExists(atPath: cachesURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: cachesURL)
        let count = fileManager.countItems(in: cachesURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [cachesURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let cachesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches")
        
        guard fileManager.fileExists(atPath: cachesURL.path) else {
            // error parameter before duration to match struct's parameter order
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        // Delete contents of caches directory safely
        // safeDeleteContents now handles permission errors gracefully and continues
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: cachesURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        // If we deleted something, consider it a success even if some items were skipped
        return CleanupResult(
            category: type,
            success: itemsDeleted > 0 || spaceFreed > 0,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct SystemCachesCategory: CleanupCategory {
    let type: CleanupCategoryType = .systemCaches
    let requiresAdmin = true
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let systemCachesURL = URL(fileURLWithPath: "/Library/Caches")
        
        guard fileManager.fileExists(atPath: systemCachesURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: systemCachesURL)
        let count = fileManager.countItems(in: systemCachesURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [systemCachesURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        // This method is not used directly for privileged categories.
        // Cleaning is done via cleanWithAuthorization to handle authorization.
        throw CleanupError.authorizationFailed
    }
}

struct UserLogsCategory: CleanupCategory {
    let type: CleanupCategoryType = .userLogs
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let logsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        
        guard fileManager.fileExists(atPath: logsURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: logsURL)
        let count = fileManager.countItems(in: logsURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [logsURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let logsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        
        guard fileManager.fileExists(atPath: logsURL.path) else {
            // error parameter before duration to match struct's parameter order
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: logsURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        // error parameter before duration to match struct's parameter order (not needed here since no error)
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct SystemLogsCategory: CleanupCategory {
    let type: CleanupCategoryType = .systemLogs
    let requiresAdmin = true
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let logsURL = URL(fileURLWithPath: "/var/log")
        
        guard fileManager.fileExists(atPath: logsURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: logsURL)
        let count = fileManager.countItems(in: logsURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [logsURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        // This method is not used directly for privileged categories.
        // Cleaning is done via cleanWithAuthorization to handle authorization.
        throw CleanupError.authorizationFailed
    }
}

struct SafariCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .safariCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let safariCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Safari")
        
        guard fileManager.fileExists(atPath: safariCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: safariCacheURL)
        let count = fileManager.countItems(in: safariCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [safariCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let safariCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Safari")
        
        guard fileManager.fileExists(atPath: safariCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        // Safari cache may have permission issues - handle gracefully
        do {
            let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: safariCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
            return CleanupResult(
                category: type,
                success: true,
                itemsDeleted: itemsDeleted,
                spaceFreed: spaceFreed,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            // If we can't delete Safari cache, return partial success
            return CleanupResult(
                category: type,
                success: false,
                itemsDeleted: 0,
                spaceFreed: 0,
                error: .deletionFailed("Safari cache is protected and cannot be cleaned"),
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }
}

struct ChromeCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .chromeCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let chromeCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Google/Chrome")
        
        guard fileManager.fileExists(atPath: chromeCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: chromeCacheURL)
        let count = fileManager.countItems(in: chromeCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [chromeCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let chromeCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Google/Chrome")
        
        guard fileManager.fileExists(atPath: chromeCacheURL.path) else {
            // error parameter before duration to match struct's parameter order
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: chromeCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct FirefoxCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .firefoxCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        // Firefox cache is typically in Application Support, not Caches
        let firefoxCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        
        guard fileManager.fileExists(atPath: firefoxCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        // Look for cache directories in Firefox profiles
        var totalSize: Int64 = 0
        var totalCount = 0
        
        if let profiles = try? fileManager.contentsOfDirectory(at: firefoxCacheURL, includingPropertiesForKeys: nil) {
            for profile in profiles {
                let cacheDir = profile.appendingPathComponent("cache2")
                if fileManager.fileExists(atPath: cacheDir.path) {
                    totalSize += fileManager.sizeOfDirectory(at: cacheDir)
                    totalCount += fileManager.countItems(in: cacheDir)
                }
            }
        }
        
        return CleanupScanResult(
            category: type,
            itemCount: totalCount,
            estimatedSize: totalSize,
            paths: [firefoxCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let firefoxCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        
        guard fileManager.fileExists(atPath: firefoxCacheURL.path) else {
            // error parameter before duration to match struct's parameter order
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        var itemsDeleted = 0
        var spaceFreed: Int64 = 0
        
        if let profiles = try? fileManager.contentsOfDirectory(at: firefoxCacheURL, includingPropertiesForKeys: nil) {
            for profile in profiles {
                let cacheDir = profile.appendingPathComponent("cache2")
                if fileManager.fileExists(atPath: cacheDir.path) {
                    let (deleted, freed) = try fileManager.safeDeleteContents(of: cacheDir, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
                    itemsDeleted += deleted
                    spaceFreed += freed
                }
            }
        }
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct DownloadsCategory: CleanupCategory {
    let type: CleanupCategoryType = .downloads
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        guard fileManager.fileExists(atPath: downloadsURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: downloadsURL)
        let count = fileManager.countItems(in: downloadsURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [downloadsURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw CleanupError.fileNotFound
        }
        
        guard fileManager.fileExists(atPath: downloadsURL.path) else {
            // error parameter before duration to match struct's parameter order
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: downloadsURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct TrashCategory: CleanupCategory {
    let type: CleanupCategoryType = .trash
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        
        // Use the proper API to get Trash directory
        guard let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        guard fileManager.fileExists(atPath: trashURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: trashURL)
        let count = fileManager.countItems(in: trashURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [trashURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        
        // Use the proper API to get Trash directory
        guard let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        guard fileManager.fileExists(atPath: trashURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        // Trash may have permission issues - handle gracefully
        do {
            let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: trashURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
            return CleanupResult(
                category: type,
                success: true,
                itemsDeleted: itemsDeleted,
                spaceFreed: spaceFreed,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            // If we can't delete Trash, return partial success
            return CleanupResult(
                category: type,
                success: false,
                itemsDeleted: 0,
                spaceFreed: 0,
                error: .deletionFailed("Trash is protected and cannot be cleaned"),
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }
}

// MARK: - New Cleanup Categories

struct XcodeDerivedDataCategory: CleanupCategory {
    let type: CleanupCategoryType = .xcodeDerivedData
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let derivedDataURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        
        guard fileManager.fileExists(atPath: derivedDataURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: derivedDataURL)
        let count = fileManager.countItems(in: derivedDataURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [derivedDataURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let derivedDataURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        
        guard fileManager.fileExists(atPath: derivedDataURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: derivedDataURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct XcodeArchivesCategory: CleanupCategory {
    let type: CleanupCategoryType = .xcodeArchives
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let archivesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/Archives")
        
        guard fileManager.fileExists(atPath: archivesURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: archivesURL)
        let count = fileManager.countItems(in: archivesURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [archivesURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let archivesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/Archives")
        
        guard fileManager.fileExists(atPath: archivesURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: archivesURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct NPMCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .npmCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let npmCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".npm")
        
        guard fileManager.fileExists(atPath: npmCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: npmCacheURL)
        let count = fileManager.countItems(in: npmCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [npmCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let npmCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".npm")
        
        guard fileManager.fileExists(atPath: npmCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: npmCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct CocoaPodsCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .cocoapodsCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let cocoapodsCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CocoaPods")
        
        guard fileManager.fileExists(atPath: cocoapodsCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: cocoapodsCacheURL)
        let count = fileManager.countItems(in: cocoapodsCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [cocoapodsCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let cocoapodsCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CocoaPods")
        
        guard fileManager.fileExists(atPath: cocoapodsCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: cocoapodsCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct HomebrewCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .homebrewCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let homebrewCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew")
        
        guard fileManager.fileExists(atPath: homebrewCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: homebrewCacheURL)
        let count = fileManager.countItems(in: homebrewCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [homebrewCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let homebrewCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew")
        
        guard fileManager.fileExists(atPath: homebrewCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: homebrewCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct DockerCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .dockerCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let dockerURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0")
        
        guard fileManager.fileExists(atPath: dockerURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: dockerURL)
        let count = fileManager.countItems(in: dockerURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [dockerURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let dockerURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0")
        
        guard fileManager.fileExists(atPath: dockerURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: dockerURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct EdgeCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .edgeCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let edgeCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.microsoft.edgemac")
        
        guard fileManager.fileExists(atPath: edgeCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: edgeCacheURL)
        let count = fileManager.countItems(in: edgeCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [edgeCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let edgeCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.microsoft.edgemac")
        
        guard fileManager.fileExists(atPath: edgeCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: edgeCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct BraveCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .braveCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let braveCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser")
        
        guard fileManager.fileExists(atPath: braveCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: braveCacheURL)
        let count = fileManager.countItems(in: braveCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [braveCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let braveCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser")
        
        guard fileManager.fileExists(atPath: braveCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: braveCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct SpotifyCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .spotifyCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let spotifyCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.spotify.client")
        
        guard fileManager.fileExists(atPath: spotifyCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: spotifyCacheURL)
        let count = fileManager.countItems(in: spotifyCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [spotifyCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let spotifyCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.spotify.client")
        
        guard fileManager.fileExists(atPath: spotifyCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: spotifyCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct SlackCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .slackCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let slackCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.tinyspeck.slackmacgap")
        
        guard fileManager.fileExists(atPath: slackCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: slackCacheURL)
        let count = fileManager.countItems(in: slackCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [slackCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let slackCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.tinyspeck.slackmacgap")
        
        guard fileManager.fileExists(atPath: slackCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: slackCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct ZoomCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .zoomCache
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let zoomCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/us.zoom.xos")
        
        guard fileManager.fileExists(atPath: zoomCacheURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: zoomCacheURL)
        let count = fileManager.countItems(in: zoomCacheURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [zoomCacheURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let zoomCacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/us.zoom.xos")
        
        guard fileManager.fileExists(atPath: zoomCacheURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: zoomCacheURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct iOSBackupsCategory: CleanupCategory {
    let type: CleanupCategoryType = .iosBackups
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let fileManager = FileManager.default
        let backupsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MobileSync/Backup")
        
        guard fileManager.fileExists(atPath: backupsURL.path) else {
            return CleanupScanResult(category: type, itemCount: 0, estimatedSize: 0, paths: [])
        }
        
        let size = fileManager.sizeOfDirectory(at: backupsURL)
        let count = fileManager.countItems(in: backupsURL)
        
        return CleanupScanResult(
            category: type,
            itemCount: count,
            estimatedSize: size,
            paths: [backupsURL]
        )
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let fileManager = FileManager.default
        let backupsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MobileSync/Backup")
        
        guard fileManager.fileExists(atPath: backupsURL.path) else {
            return CleanupResult(category: type, success: true, duration: Date().timeIntervalSince(startTime))
        }
        
        let (itemsDeleted, spaceFreed) = try fileManager.safeDeleteContents(of: backupsURL, category: type.displayName, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
        
        return CleanupResult(
            category: type,
            success: true,
            itemsDeleted: itemsDeleted,
            spaceFreed: spaceFreed,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

