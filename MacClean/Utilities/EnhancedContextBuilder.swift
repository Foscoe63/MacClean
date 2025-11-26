import Foundation

@MainActor
class EnhancedContextBuilder {
    static func buildContext(cleanupEngine: CleanupEngine, preferencesManager: PreferencesManager) async -> EnhancedAIContext {
        let fileManager = FileManager.default
        
        // Get basic file system info
        var totalDiskSpace: Int64 = 0
        var availableDiskSpace: Int64 = 0
        var homeDirectoryContents: [String] = []
        let recentFiles: [String] = []
        let fileModificationDates: [String: Date] = [:]
        
        if let homeURL = fileManager.urls(for: .userDirectory, in: .userDomainMask).first,
           let attributes = try? fileManager.attributesOfFileSystem(forPath: homeURL.path) {
            totalDiskSpace = (attributes[.systemSize] as? Int64) ?? 0
            availableDiskSpace = (attributes[.systemFreeSize] as? Int64) ?? 0
            
            // Get home directory contents
            if let contents = try? fileManager.contentsOfDirectory(atPath: homeURL.path) {
                homeDirectoryContents = Array(contents.prefix(20))
            }
        }
        
        // Get system health metrics
        let healthManager = SystemHealthManager(cleanupEngine: cleanupEngine)
        let health = await healthManager.calculateHealth()
        
        let systemHealthMetrics = EnhancedAIContext.SystemHealthMetrics(
            diskUsagePercent: health.performanceMetrics.diskUsagePercent,
            cpuUsagePercent: health.performanceMetrics.cpuUsagePercent,
            memoryUsagePercent: health.performanceMetrics.memoryUsagePercent,
            diskHealthScore: health.diskHealthScore,
            lastCleanupDate: health.maintenanceSchedule.lastCleanup,
            daysSinceLastCleanup: health.maintenanceSchedule.daysSinceLastCleanup
        )
        
        // Get user preferences history
        let historyManager = CleanupHistoryManager()
        let entries = historyManager.entries
        
        var categoryFrequency: [String: Int] = [:]
        var totalSpaceFreed: Int64 = 0
        
        for entry in entries {
            totalSpaceFreed += entry.spaceFreed
            for category in entry.categories {
                categoryFrequency[category, default: 0] += 1
            }
        }
        
        let averageSpaceFreed = entries.isEmpty ? 0 : totalSpaceFreed / Int64(entries.count)
        
        // Calculate average cleanup frequency
        let averageFrequency: Double
        if entries.count >= 2 {
            let sorted = entries.sorted { $0.timestamp < $1.timestamp }
            var totalDays = 0
            for i in 1..<sorted.count {
                if let days = Calendar.current.dateComponents([.day], from: sorted[i-1].timestamp, to: sorted[i].timestamp).day {
                    totalDays += days
                }
            }
            averageFrequency = Double(totalDays) / Double(sorted.count - 1)
        } else {
            averageFrequency = 7.0
        }
        
        let userPreferencesHistory = EnhancedAIContext.UserPreferencesHistory(
            frequentlyCleanedCategories: categoryFrequency,
            averageCleanupFrequency: averageFrequency,
            preferredCleanupTime: entries.first?.timestamp,
            totalCleanups: entries.count,
            averageSpaceFreed: averageSpaceFreed
        )
        
        return EnhancedAIContext(
            fileSystemInfo: EnhancedAIContext.FileSystemInfo(
                totalDiskSpace: totalDiskSpace,
                availableDiskSpace: availableDiskSpace,
                homeDirectoryContents: homeDirectoryContents,
                recentFiles: recentFiles,
                fileModificationDates: fileModificationDates
            ),
            fileModificationDates: fileModificationDates,
            fileAccessPatterns: [:], // Would require additional file system monitoring
            systemHealthMetrics: systemHealthMetrics,
            userPreferencesHistory: userPreferencesHistory
        )
    }
}

