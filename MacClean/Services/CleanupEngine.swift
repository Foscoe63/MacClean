import Foundation
import SwiftUI

@Observable
class CleanupEngine {
    var isCleaning = false
    var currentProgress: Double = 0.0
    var currentStatus: String = ""
    var results: [CleanupResult] = []
    var summary: CleanupSummary?
    
    private var categories: [any CleanupCategory] = []
    
    init() {
        setupCategories()
    }
    
    private func setupCategories() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        func folder(_ type: CleanupCategoryType, _ relativePath: String) -> DirectoryCleanupCategory {
            DirectoryCleanupCategory(type: type, directories: [home.appendingPathComponent(relativePath)])
        }
        
        categories = [
            folder(.userCaches, "Library/Caches"),
            SystemCachesCategory(),
            folder(.userLogs, "Library/Logs"),
            SystemLogsCategory(),
            // Browsers
            folder(.safariCache, "Library/Caches/com.apple.Safari"),
            folder(.chromeCache, "Library/Caches/Google/Chrome"),
            FirefoxCacheCategory(),
            folder(.edgeCache, "Library/Caches/com.microsoft.edgemac"),
            folder(.braveCache, "Library/Caches/BraveSoftware/Brave-Browser"),
            // Personal folders
            DirectoryCleanupCategory(
                type: .downloads,
                directories: Array(fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).prefix(1))
            ),
            DirectoryCleanupCategory(
                type: .trash,
                directories: Array(fileManager.urls(for: .trashDirectory, in: .userDomainMask).prefix(1))
            ),
            // Developer tools
            folder(.xcodeDerivedData, "Library/Developer/Xcode/DerivedData"),
            folder(.xcodeArchives, "Library/Developer/Xcode/Archives"),
            folder(.npmCache, ".npm"),
            folder(.cocoapodsCache, "Library/Caches/CocoaPods"),
            folder(.homebrewCache, "Library/Caches/Homebrew"),
            // Application-specific
            folder(.spotifyCache, "Library/Caches/com.spotify.client"),
            folder(.slackCache, "Library/Caches/com.tinyspeck.slackmacgap"),
            folder(.zoomCache, "Library/Caches/us.zoom.xos"),
            // System maintenance
            folder(.iosBackups, "Library/Application Support/MobileSync/Backup")
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

        // Scans finish in any order; keep the list in a stable, predictable order
        let order = CleanupCategoryType.allCases
        items.sort { (order.firstIndex(of: $0.category) ?? 0) < (order.firstIndex(of: $1.category) ?? 0) }

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
            // Stop before starting the next category once the user cancels
            if Task.isCancelled { break }
            
            guard let category = categories.first(where: { $0.type == item.category }) else { continue }
            
            let progress = Double(index) / totalCategories
            let categoryName = category.name
            progressHandler(progress, "Cleaning \(categoryName)...")
            currentProgress = progress
            currentStatus = "Cleaning \(categoryName)..."
            
            do {
                var result: CleanupResult
                if category.requiresAdmin {
                    // Runs a scoped shell command behind the standard macOS administrator prompt.
                    // These items are always deleted permanently; per-file exclusions do not apply.
                    result = try await cleanWithAuthorization(category: category)
                } else if category.type == .trash {
                    // Moving Trash items to the Trash does nothing, so emptying it is always permanent
                    result = try await category.clean(moveToTrash: false, files: item.files, protectedPaths: protectedPaths)
                } else {
                    result = try await category.clean(moveToTrash: moveToTrash, files: item.files, protectedPaths: protectedPaths)
                    result.movedToTrash = moveToTrash
                }
                results.append(result)
            } catch let error as CleanupError {
                results.append(CleanupResult(category: category.type, success: false, error: error))
            } catch {
                results.append(CleanupResult(category: category.type, success: false, error: .unknown(error)))
            }
        }
        
        let wasCancelled = Task.isCancelled
        let finalStatus = wasCancelled ? "Cancelled" : "Complete"
        progressHandler(1.0, finalStatus)
        currentProgress = 1.0
        currentStatus = finalStatus
        
        summary = createSummary(wasCancelled: wasCancelled)
        isCleaning = false
    }
    
    /// Apple-owned cache folders that cannot be removed even with administrator rights.
    private static let protectedSystemCacheNames = [
        "com.apple.amsengagementd.classicdatavault",
        "com.apple.aned",
        "com.apple.aneuserd"
    ]
    
    /// Cleans a system location through `osascript ... with administrator privileges`.
    /// The shell commands are fixed strings scoped to one folder; nothing user-provided is interpolated.
    private func cleanWithAuthorization(category: any CleanupCategory) async throws -> CleanupResult {
        let startTime = Date()
        
        let shellCommand: String
        switch category.type {
        case .systemCaches:
            // Remove each top-level cache folder except the protected Apple ones
            let exclusions = Self.protectedSystemCacheNames
                .map { "! -name '\($0)'" }
                .joined(separator: " ")
            shellCommand = "/usr/bin/find /Library/Caches -mindepth 1 -maxdepth 1 \(exclusions) -exec /bin/rm -rf {} + 2>/dev/null; exit 0"
        case .systemLogs:
            // Only rotated and archived logs; live log files and folders stay in place
            shellCommand = "/usr/bin/find /private/var/log -type f \\( -name '*.gz' -o -name '*.bz2' -o -name '*.old' -o -name '*.[0-9]' \\) -delete 2>/dev/null; exit 0"
        default:
            throw CleanupError.invalidPath
        }
        
        let before = try await category.scan()
        try await Self.runWithAdministratorPrivileges(shellCommand)
        let after = try await category.scan()
        
        return CleanupResult(
            category: category.type,
            success: true,
            itemsDeleted: max(0, before.itemCount - after.itemCount),
            spaceFreed: max(0, before.estimatedSize - after.estimatedSize),
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    /// Runs a shell command behind the macOS administrator password prompt without blocking the UI.
    private static func runWithAdministratorPrivileges(_ shellCommand: String) async throws {
        let escapedCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedCommand)\" with administrator privileges"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { @Sendable finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        
        guard status == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            // -128 is AppleScript's "User canceled" error
            if errorText.contains("-128") || errorText.localizedCaseInsensitiveContains("canceled") {
                throw CleanupError.authorizationFailed
            }
            throw CleanupError.deletionFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    private func createSummary(wasCancelled: Bool) -> CleanupSummary {
        let totalItems = results.reduce(0) { $0 + $1.itemsDeleted }
        let freed = results.filter { !$0.movedToTrash }.reduce(0) { $0 + $1.spaceFreed }
        let movedToTrash = results.filter { $0.movedToTrash }.reduce(0) { $0 + $1.spaceFreed }
        let successful = results.filter { $0.success }.count
        let failed = results.filter { !$0.success }.count
        
        return CleanupSummary(
            totalItemsDeleted: totalItems,
            totalSpaceFreed: freed,
            totalSpaceMovedToTrash: movedToTrash,
            successfulCategories: successful,
            failedCategories: failed,
            wasCancelled: wasCancelled,
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

/// A category that cleans the contents of one or more fixed folders.
/// Scanning and deleting run off the main thread through `BackgroundFileWork`.
struct DirectoryCleanupCategory: CleanupCategory {
    let type: CleanupCategoryType
    let directories: [URL]
    let requiresAdmin = false
    
    func scan() async throws -> CleanupScanResult {
        let existing = directories.filter { FileManager.default.fileExists(atPath: $0.path) }
        let usage = await BackgroundFileWork.usage(of: existing)
        return CleanupScanResult(category: type, itemCount: usage.count, estimatedSize: usage.size, paths: existing)
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        let startTime = Date()
        let outcome = try await BackgroundFileWork.deleteContents(
            of: directories,
            category: type.displayName,
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

/// Firefox keeps one disk cache per profile in `~/Library/Caches/Firefox/Profiles/<profile>/cache2`.
struct FirefoxCacheCategory: CleanupCategory {
    let type: CleanupCategoryType = .firefoxCache
    let requiresAdmin = false
    
    private var cacheDirectories: [URL] {
        let fileManager = FileManager.default
        let profilesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Firefox/Profiles")
        let profiles = (try? fileManager.contentsOfDirectory(at: profilesURL, includingPropertiesForKeys: nil)) ?? []
        return profiles
            .map { $0.appendingPathComponent("cache2") }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
    
    func scan() async throws -> CleanupScanResult {
        let directories = cacheDirectories
        let usage = await BackgroundFileWork.usage(of: directories)
        // Report only the cache2 folders so the file preview never lists other profile data
        return CleanupScanResult(category: type, itemCount: usage.count, estimatedSize: usage.size, paths: directories)
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        try await DirectoryCleanupCategory(type: type, directories: cacheDirectories)
            .clean(moveToTrash: moveToTrash, protectedPaths: protectedPaths)
    }
}

/// Top-level folders in `/Library/Caches`. Cleaned by `CleanupEngine.cleanWithAuthorization`.
struct SystemCachesCategory: CleanupCategory {
    let type: CleanupCategoryType = .systemCaches
    let requiresAdmin = true
    
    func scan() async throws -> CleanupScanResult {
        let systemCachesURL = URL(fileURLWithPath: "/Library/Caches")
        let usage = await BackgroundFileWork.usage(of: [systemCachesURL])
        return CleanupScanResult(category: type, itemCount: usage.count, estimatedSize: usage.size, paths: [systemCachesURL])
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        // Privileged categories are cleaned through CleanupEngine.cleanWithAuthorization
        throw CleanupError.authorizationFailed
    }
}

/// Rotated and archived logs in `/private/var/log`. Cleaned by `CleanupEngine.cleanWithAuthorization`.
struct SystemLogsCategory: CleanupCategory {
    let type: CleanupCategoryType = .systemLogs
    let requiresAdmin = true
    
    private let logsURL = URL(fileURLWithPath: "/private/var/log")
    
    func scan() async throws -> CleanupScanResult {
        let usage = await BackgroundFileWork.rotatedLogUsage(in: logsURL)
        return CleanupScanResult(category: type, itemCount: usage.count, estimatedSize: usage.size, paths: [logsURL])
    }
    
    func scanDetailed() async throws -> [CleanupFile] {
        // The preview only lists what the cleanup would actually remove
        await CleanupCategoryDefaults.scanFiles(in: [logsURL])
            .filter { BackgroundFileWork.isRotatedLog($0.url) }
    }
    
    func clean(moveToTrash: Bool, protectedPaths: [String]) async throws -> CleanupResult {
        // Privileged categories are cleaned through CleanupEngine.cleanWithAuthorization
        throw CleanupError.authorizationFailed
    }
}
