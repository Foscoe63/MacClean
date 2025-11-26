import Foundation

struct EnhancedAIContext {
    let fileSystemInfo: FileSystemInfo
    let fileModificationDates: [String: Date]
    let fileAccessPatterns: [String: AccessPattern]
    let systemHealthMetrics: SystemHealthMetrics
    let userPreferencesHistory: UserPreferencesHistory
    
    struct FileSystemInfo {
        let totalDiskSpace: Int64
        let availableDiskSpace: Int64
        let homeDirectoryContents: [String]
        let recentFiles: [String]
        let fileModificationDates: [String: Date]
    }
    
    struct AccessPattern {
        let filePath: String
        let lastAccessed: Date?
        let accessCount: Int
        let averageDaysBetweenAccess: Double?
    }
    
    struct SystemHealthMetrics {
        let diskUsagePercent: Double
        let cpuUsagePercent: Double?
        let memoryUsagePercent: Double?
        let diskHealthScore: Double // 0.0 to 1.0
        let lastCleanupDate: Date?
        let daysSinceLastCleanup: Int?
    }
    
    struct UserPreferencesHistory {
        let frequentlyCleanedCategories: [String: Int]
        let averageCleanupFrequency: Double // days
        let preferredCleanupTime: Date?
        let totalCleanups: Int
        let averageSpaceFreed: Int64
    }
}




