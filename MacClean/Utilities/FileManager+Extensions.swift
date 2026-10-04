import Foundation

extension FileManager {
    func sizeOfDirectory(at url: URL) -> Int64 {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            // Check if this is a directory
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                continue
            }
            
            // Only count files, not directory entries
            if !isDirectory.boolValue {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    func countItems(in url: URL) -> Int {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        
        return enumerator.allObjects.count
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
    private func isAllowedCleanupLocation(_ path: String, homeDirectory: String) -> Bool {
        let allowedRoots = [
            "\(homeDirectory)/Library/Application Support/MobileSync/Backup"
        ]
        // Only the contents are allowed, never the root folder itself
        return allowedRoots.contains { Self.isPath(path, inside: $0) && !Self.isSamePath(path, $0) }
    }

    /// Deletes or trashes a single item after checking it against system, user and custom protected paths.
    /// - Returns: The item's new location in the Trash, or `nil` when it was deleted permanently.
    @discardableResult
    func safeDelete(at url: URL, moveToTrash: Bool = true, protectedPaths: [String] = []) throws -> URL? {
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
    
    func safeDeleteContents(of url: URL, category: String? = nil, moveToTrash: Bool = true, protectedPaths: [String] = []) throws -> (itemsDeleted: Int, spaceFreed: Int64) {
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
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        var itemsDeleted = 0
        var spaceFreed: Int64 = 0
        var logEntries: [DeletionLogEntry] = []
        
        // Use provided category or fall back to directory name
        let categoryName = category ?? url.lastPathComponent
        
        for item in contents {
            // Stop between items when the user cancels; whatever is already removed stays logged
            if Task.isCancelled { break }
            
            if protectedFolders.contains(item.lastPathComponent) {
                continue
            }
            
            // Get size before attempting deletion
            var itemSize: Int64 = 0
            var isItemDirectory: ObjCBool = false
            if fileExists(atPath: item.path, isDirectory: &isItemDirectory) {
                if isItemDirectory.boolValue {
                    itemSize = sizeOfDirectory(at: item)
                } else if let fileSize = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    itemSize = Int64(fileSize)
                }
            }
            
            // Try to delete, but continue if it fails (permission denied, protected, etc.)
            do {
                let trashURL = try safeDelete(at: item, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
                itemsDeleted += 1
                spaceFreed += itemSize
                logEntries.append(DeletionLogEntry(
                    filePath: item.path,
                    fileSize: itemSize,
                    category: categoryName,
                    trashPath: trashURL?.path
                ))
            } catch {
                logEntries.append(DeletionLogEntry(
                    filePath: item.path,
                    fileSize: itemSize,
                    category: categoryName,
                    success: false,
                    errorMessage: error.localizedDescription
                ))
            }
        }
        
        DeletionLogManager.shared.logDeletions(logEntries)
        return (itemsDeleted, spaceFreed)
    }
    
    func safeDeleteFiles(_ files: [CleanupFile], category: String, moveToTrash: Bool = true, protectedPaths: [String] = []) throws -> (itemsDeleted: Int, spaceFreed: Int64) {
        var itemsDeleted = 0
        var spaceFreed: Int64 = 0
        var logEntries: [DeletionLogEntry] = []
        
        for file in files where !file.isExcluded {
            if Task.isCancelled { break }
            
            do {
                let trashURL = try safeDelete(at: file.url, moveToTrash: moveToTrash, protectedPaths: protectedPaths)
                itemsDeleted += 1
                spaceFreed += file.size
                logEntries.append(DeletionLogEntry(
                    filePath: file.path,
                    fileSize: file.size,
                    category: category,
                    trashPath: trashURL?.path
                ))
            } catch {
                logEntries.append(DeletionLogEntry(
                    filePath: file.path,
                    fileSize: file.size,
                    category: category,
                    success: false,
                    errorMessage: error.localizedDescription
                ))
            }
        }
        
        DeletionLogManager.shared.logDeletions(logEntries)
        return (itemsDeleted, spaceFreed)
    }
}
