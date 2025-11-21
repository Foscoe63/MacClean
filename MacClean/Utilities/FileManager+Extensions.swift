import Foundation

extension FileManager {
    func sizeOfDirectory(at url: URL) -> Int64 {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
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
    
    func safeDelete(at url: URL, moveToTrash: Bool = true) throws {
        guard fileExists(atPath: url.path) else {
            throw CleanupError.fileNotFound
        }
        
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CleanupError.fileNotFound
        }
        
        let path = url.path
        
        // Get current user's home directory
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
        
        // Check system-critical paths (allow /Library/Caches and /var/log for cleanup)
        for criticalPath in criticalSystemPaths {
            if path.hasPrefix(criticalPath) && !path.hasPrefix("/Library/Caches") && !path.hasPrefix("/var/log") {
                throw CleanupError.deletionFailed("Cannot delete system-critical path: \(criticalPath)")
            }
        }
        
        // Check protected user directories (allow Downloads and Trash with warning)
        for protectedPath in protectedUserPaths {
            if path.hasPrefix(protectedPath) {
                throw CleanupError.deletionFailed("Cannot delete protected user directory: \(protectedPath)")
            }
        }
        
        // Additional protection: don't delete anything in /Applications
        if path.hasPrefix("/Applications") {
            throw CleanupError.deletionFailed("Cannot delete files in /Applications directory")
        }
        
        if moveToTrash {
            // Move to Trash using NSFileManager
            try trashItem(at: url, resultingItemURL: nil)
        } else {
            // Permanent deletion
            if isDirectory.boolValue {
                try removeItem(at: url)
            } else {
                try removeItem(at: url)
            }
        }
    }
    
    func safeDeleteContents(of url: URL, category: String? = nil, moveToTrash: Bool = true) throws -> (itemsDeleted: Int, spaceFreed: Int64) {
        guard fileExists(atPath: url.path) else {
            throw CleanupError.fileNotFound
        }
        
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
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
        
        // Use provided category or fall back to directory name
        let categoryName = category ?? url.lastPathComponent
        
        for item in contents {
            // Skip protected Apple system folders
            let itemName = item.lastPathComponent
            if protectedFolders.contains(itemName) {
                continue
            }
            
            // Get size before attempting deletion
            var itemSize: Int64 = 0
            if let fileSize = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                itemSize = Int64(fileSize)
            }
            
            // Try to delete, but continue if it fails (permission denied, etc.)
            do {
                try safeDelete(at: item, moveToTrash: moveToTrash)
                itemsDeleted += 1
                
                // Only count space as freed if permanently deleted (not moved to Trash)
                // When moved to Trash, files still take up space, just in a different location
                if !moveToTrash {
                    spaceFreed += itemSize
                }
                
                // Log successful deletion
                DeletionLogManager.shared.logDeletion(
                    filePath: item.path,
                    fileSize: itemSize,
                    category: categoryName,
                    success: true
                )
            } catch {
                // Log failed deletion
                DeletionLogManager.shared.logDeletion(
                    filePath: item.path,
                    fileSize: itemSize,
                    category: categoryName,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                
                // Skip items that can't be deleted (protected files)
                // Continue with other items
                continue
            }
        }
        
        return (itemsDeleted, spaceFreed)
    }
}

