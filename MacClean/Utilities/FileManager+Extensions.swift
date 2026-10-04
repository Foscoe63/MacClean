import Foundation

extension FileManager {
    /// Disk space used by the regular files under `url` and how many there are, in a single pass.
    /// Uses allocated size so sparse and compressed files report what they really occupy.
    nonisolated func directoryUsage(at url: URL) -> (size: Int64, count: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return (0, 0)
        }
        
        var totalSize: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            count += 1
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        
        return (totalSize, count)
    }
    
    nonisolated func sizeOfDirectory(at url: URL) -> Int64 {
        directoryUsage(at: url).size
    }
    
    nonisolated func countItems(in url: URL) -> Int {
        directoryUsage(at: url).count
    }
    
    /// Standardizes a path and resolves symlinks so prefix checks cannot be bypassed with `..` or links.
    nonisolated static func normalizedPaths(for path: String) -> [String] {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        return resolved.isEmpty || resolved == standardized ? [standardized] : [standardized, resolved]
    }

    /// Returns true when `path` is `root` itself or lives inside it, compared by whole path components.
    /// `/Users/me/Desktop` is inside `/Users/me/Desktop` but `/Users/me/Desktop Backup` is not.
    nonisolated static func isPath(_ path: String, inside root: String) -> Bool {
        guard !root.isEmpty else { return false }
        for candidate in normalizedPaths(for: path) {
            for base in normalizedPaths(for: root) {
                if base == "/" || candidate == base || candidate.hasPrefix(base + "/") {
                    return true
                }
            }
        }
        return false
    }

    /// Returns true when both paths point at the same location after normalization.
    nonisolated static func isSamePath(_ lhs: String, _ rhs: String) -> Bool {
        !Set(normalizedPaths(for: lhs)).isDisjoint(with: normalizedPaths(for: rhs))
    }

    /// Locations inside otherwise protected folders that specific cleanup categories are allowed to clean.
    nonisolated private func isAllowedCleanupLocation(_ path: String, homeDirectory: String) -> Bool {
        let allowedRoots = [
            "\(homeDirectory)/Library/Application Support/MobileSync/Backup"
        ]
        // Only the contents are allowed, never the root folder itself
        return allowedRoots.contains { Self.isPath(path, inside: $0) && !Self.isSamePath(path, $0) }
    }

    /// Deletes or trashes a single item after checking it against system, user and custom protected paths.
    /// - Returns: The item's new location in the Trash, or `nil` when it was deleted permanently.
    @discardableResult
    nonisolated func safeDelete(at url: URL, moveToTrash: Bool = true, protectedPaths: [String] = []) throws -> URL? {
        // attributesOfItem does not follow symlinks, so broken links can still be removed
        guard (try? attributesOfItem(atPath: url.path)) != nil else {
            throw CleanupError.fileNotFound
        }
        
        let path = url.path
        let homeDirectory = homeDirectoryForCurrentUser.path
        
        // Safety check: don't delete system-critical paths
        let criticalSystemPaths = [
            "/System",
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/Applications",
            "/private",
            "/opt",
            "/var/db",
            "/var/root"
        ]
        
        // Protected user directories (always protect these)
        let protectedUserPaths = [
            "\(homeDirectory)/Documents",
            "\(homeDirectory)/Desktop",
            "\(homeDirectory)/Movies",
            "\(homeDirectory)/Music",
            "\(homeDirectory)/Pictures",
            "\(homeDirectory)/Library/Application Support",
            "\(homeDirectory)/Library/Preferences",
            "\(homeDirectory)/Library/Keychains",
            "\(homeDirectory)/Library/Mail",
            "\(homeDirectory)/Library/Calendars",
            "\(homeDirectory)/Library/Contacts",
            "\(homeDirectory)/Library/Messages",
            "\(homeDirectory)/Library/Safari",
            "\(homeDirectory)/Library/WebKit"
        ]
        
        // Never delete the home folder itself
        guard !Self.isSamePath(path, homeDirectory) else {
            throw CleanupError.deletionFailed("Cannot delete the home folder")
        }
        
        for criticalPath in criticalSystemPaths where Self.isPath(path, inside: criticalPath) {
            throw CleanupError.deletionFailed("Cannot delete system-critical path: \(criticalPath)")
        }
        
        if !isAllowedCleanupLocation(path, homeDirectory: homeDirectory) {
            for protectedPath in protectedUserPaths where Self.isPath(path, inside: protectedPath) {
                throw CleanupError.deletionFailed("Cannot delete protected user directory: \(protectedPath)")
            }
        }
        
        for protectedPath in protectedPaths where Self.isPath(path, inside: protectedPath) {
            throw CleanupError.deletionFailed("Cannot delete user-protected path: \(protectedPath)")
        }
        
        if moveToTrash {
            var resultingURL: NSURL?
            try trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL.map { $0 as URL }
        }
        
        try removeItem(at: url)
        return nil
    }
    
    /// Deletes or trashes everything inside `url`, skipping protected items and anything that fails.
    /// Stops early when the current task is cancelled.
    nonisolated func safeDeleteContents(of url: URL, category: String, moveToTrash: Bool = true, protectedPaths: [String] = []) throws -> DeletionOutcome {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CleanupError.fileNotFound
        }
        guard isDirectory.boolValue else {
            throw CleanupError.invalidPath
        }
        
        // Protected Apple system folders that shouldn't be deleted
        let protectedFolders = [
            "com.apple.HomeKit"
        ]
        
        let contents = try contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        var outcome = DeletionOutcome()
        
        for item in contents {
            if Task.isCancelled { break }
            if protectedFolders.contains(item.lastPathComponent) { continue }
            
            // Measure before deleting so the freed space can be reported
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            let itemSize = values?.isDirectory == true
                ? directoryUsage(at: item).size
                : Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            
            outcome.record(
                deleting: item,
                size: itemSize,
                category: category,
                using: { try safeDelete(at: item, moveToTrash: moveToTrash, protectedPaths: protectedPaths) }
            )
        }
        
        return outcome
    }
    
    /// Deletes or trashes the given files individually, skipping the ones the user excluded.
    nonisolated func safeDeleteFiles(_ files: [CleanupFile], category: String, moveToTrash: Bool = true, protectedPaths: [String] = []) -> DeletionOutcome {
        var outcome = DeletionOutcome()
        
        for file in files where !file.isExcluded {
            if Task.isCancelled { break }
            
            outcome.record(
                deleting: file.url,
                size: file.size,
                category: category,
                using: { try safeDelete(at: file.url, moveToTrash: moveToTrash, protectedPaths: protectedPaths) }
            )
        }
        
        return outcome
    }
}

/// What a batch of deletions achieved, plus the log entries to persist on the main actor.
nonisolated struct DeletionOutcome: Sendable {
    var itemsDeleted = 0
    var spaceFreed: Int64 = 0
    var logEntries: [DeletionLogEntry] = []
    
    mutating func record(deleting url: URL, size: Int64, category: String, using delete: () throws -> URL?) {
        do {
            let trashURL = try delete()
            itemsDeleted += 1
            spaceFreed += size
            logEntries.append(DeletionLogEntry(
                filePath: url.path,
                fileSize: size,
                category: category,
                trashPath: trashURL?.path
            ))
        } catch {
            logEntries.append(DeletionLogEntry(
                filePath: url.path,
                fileSize: size,
                category: category,
                success: false,
                errorMessage: error.localizedDescription
            ))
        }
    }
}

/// File-system work that must not run on the main thread.
/// `@concurrent` moves these calls onto the shared thread pool even though the app defaults to the main actor.
nonisolated enum BackgroundFileWork {
    @concurrent
    static func usage(of urls: [URL]) async -> (size: Int64, count: Int) {
        let fileManager = FileManager.default
        return urls.reduce((size: Int64(0), count: 0)) { total, url in
            guard fileManager.fileExists(atPath: url.path) else { return total }
            let usage = fileManager.directoryUsage(at: url)
            return (total.size + usage.size, total.count + usage.count)
        }
    }
    
    @concurrent
    static func deleteContents(of urls: [URL], category: String, moveToTrash: Bool, protectedPaths: [String]) async throws -> DeletionOutcome {
        var combined = DeletionOutcome()
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let outcome = try FileManager.default.safeDeleteContents(of: url, category: category, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
            combined.itemsDeleted += outcome.itemsDeleted
            combined.spaceFreed += outcome.spaceFreed
            combined.logEntries += outcome.logEntries
        }
        return combined
    }
    
    /// Rotated or archived logs that are safe to remove; live logs are left alone.
    static func isRotatedLog(_ url: URL) -> Bool {
        if ["gz", "bz2", "old"].contains(url.pathExtension) { return true }
        return url.lastPathComponent.range(of: #"\.[0-9]$"#, options: .regularExpression) != nil
    }
    
    @concurrent
    static func rotatedLogUsage(in directory: URL) async -> (size: Int64, count: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            return (0, 0)
        }
        
        var size: Int64 = 0
        var count = 0
        for case let fileURL as URL in enumerator where isRotatedLog(fileURL) {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            count += 1
            size += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return (size, count)
    }
    
    @concurrent
    static func deleteFiles(_ files: [CleanupFile], category: String, moveToTrash: Bool, protectedPaths: [String]) async -> DeletionOutcome {
        FileManager.default.safeDeleteFiles(files, category: category, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
    }
}
