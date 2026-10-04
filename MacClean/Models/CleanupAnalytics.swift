import Foundation

struct CleanupAnalytics {
    let trends: CleanupTrends
    let frequentlyCleanedCategories: [CategoryFrequency]
    let diskSpaceGrowth: DiskSpaceGrowth
    let predictions: CleanupPredictions
    
    struct CleanupTrends {
        let daily: [Date: Int64] // Date to space freed
        let weekly: [Date: Int64]
        let monthly: [Date: Int64]
        let averageSpaceFreedPerCleanup: Int64
        let totalCleanups: Int
    }
    
    struct CategoryFrequency {
        let category: String
        let cleanups: Int
        let totalSpaceFreed: Int64
        let averageSpaceFreed: Int64
        let lastCleaned: Date?
    }
    
    struct DiskSpaceGrowth {
        let growthRate: Double // GB per day
        let projectedFullDate: Date?
        let currentUsagePercent: Double
        let trendDirection: TrendDirection
        
        enum TrendDirection {
            case increasing
            case stable
            case decreasing
        }
    }
    
    struct CleanupPredictions {
        let nextRecommendedCleanup: Date?
        let estimatedSpaceAvailable: Int64
        let highPriorityCategories: [String]
        let predictedSpaceFreed: Int64
    }
}

@Observable
class CleanupAnalyticsManager {
    static let shared = CleanupAnalyticsManager()
    
    private let historyManager = CleanupHistoryManager.shared
    
    private init() {}
    
    func generateAnalytics() -> CleanupAnalytics {
        let trends = calculateTrends()
        let categoryFreq = calculateCategoryFrequency()
        let diskGrowth = calculateDiskSpaceGrowth()
        let predictions = generatePredictions(trends: trends, diskGrowth: diskGrowth)
        
        return CleanupAnalytics(
            trends: trends,
            frequentlyCleanedCategories: categoryFreq,
            diskSpaceGrowth: diskGrowth,
            predictions: predictions
        )
    }
    
    private func calculateTrends() -> CleanupAnalytics.CleanupTrends {
        let entries = historyManager.entries
        
        var daily: [Date: Int64] = [:]
        var weekly: [Date: Int64] = [:]
        var monthly: [Date: Int64] = [:]
        
        let calendar = Calendar.current
        
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            let week = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.timestamp)) ?? day
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: entry.timestamp)) ?? day
            
            daily[day, default: 0] += entry.spaceFreed
            weekly[week, default: 0] += entry.spaceFreed
            monthly[month, default: 0] += entry.spaceFreed
        }
        
        let totalSpace = entries.reduce(0) { $0 + $1.spaceFreed }
        let averageSpace = entries.isEmpty ? 0 : totalSpace / Int64(entries.count)
        
        return CleanupAnalytics.CleanupTrends(
            daily: daily,
            weekly: weekly,
            monthly: monthly,
            averageSpaceFreedPerCleanup: averageSpace,
            totalCleanups: entries.count
        )
    }
    
    private func calculateCategoryFrequency() -> [CleanupAnalytics.CategoryFrequency] {
        let entries = historyManager.entries
        
        var categoryData: [String: (cleanups: Int, totalSpace: Int64, lastCleaned: Date?)] = [:]
        
        for entry in entries {
            // Divide spaceFreed equally among all categories in this entry
            // This prevents double-counting when multiple categories are cleaned together
            let spacePerCategory = entry.categories.isEmpty ? 0 : entry.spaceFreed / Int64(entry.categories.count)
            
            for category in entry.categories {
                var data = categoryData[category] ?? (0, 0, nil)
                data.cleanups += 1
                data.totalSpace += spacePerCategory
                if let last = data.lastCleaned {
                    data.lastCleaned = max(last, entry.timestamp)
                } else {
                    data.lastCleaned = entry.timestamp
                }
                categoryData[category] = data
            }
        }
        
        return categoryData.map { category, data in
            CleanupAnalytics.CategoryFrequency(
                category: category,
                cleanups: data.cleanups,
                totalSpaceFreed: data.totalSpace,
                averageSpaceFreed: data.cleanups > 0 ? data.totalSpace / Int64(data.cleanups) : 0,
                lastCleaned: data.lastCleaned
            )
        }.sorted { $0.totalSpaceFreed > $1.totalSpaceFreed }
    }
    
    private func calculateDiskSpaceGrowth() -> CleanupAnalytics.DiskSpaceGrowth {
        guard let diskSpace = DiskSpace.current(), case let (total, free) = (diskSpace.total, diskSpace.available) else {
            return CleanupAnalytics.DiskSpaceGrowth(
                growthRate: 0,
                projectedFullDate: nil as Date?,
                currentUsagePercent: 0,
                trendDirection: CleanupAnalytics.DiskSpaceGrowth.TrendDirection.stable
            )
        }
        
        let used = total - free
        let usagePercent = Double(used) / Double(total) * 100
        
        // Calculate growth rate from history
        let entries = historyManager.entries.sorted { $0.timestamp < $1.timestamp }
        var growthRate: Double = 0
        
        if entries.count >= 2 {
            let first = entries.first!
            let last = entries.last!
            let daysBetween = Calendar.current.dateComponents([.day], from: first.timestamp, to: last.timestamp).day ?? 1
            if daysBetween > 0 {
                // Estimate growth based on cleanup frequency and space freed
                let avgSpaceFreed = entries.reduce(0) { $0 + $1.spaceFreed } / Int64(entries.count)
                let avgDaysBetweenCleanups = Double(daysBetween) / Double(entries.count - 1)
                // Rough estimate: if we free X GB every Y days, we're using X/Y GB per day
                growthRate = Double(avgSpaceFreed) / 1_000_000_000 / avgDaysBetweenCleanups
            }
        }
        
        // Project when disk will be full (if growth continues)
        let projectedFullDate: Date?
        if growthRate > 0 && free > 0 {
            let daysUntilFull = Double(free) / 1_000_000_000 / growthRate
            projectedFullDate = Calendar.current.date(byAdding: .day, value: Int(daysUntilFull), to: Date())
        } else {
            projectedFullDate = nil
        }
        
        // Determine trend direction
        let trendDirection: CleanupAnalytics.DiskSpaceGrowth.TrendDirection
        if usagePercent > 80 {
            trendDirection = .increasing
        } else if usagePercent > 60 {
            trendDirection = .stable
        } else {
            trendDirection = .decreasing
        }
        
        return CleanupAnalytics.DiskSpaceGrowth(
            growthRate: growthRate,
            projectedFullDate: projectedFullDate,
            currentUsagePercent: usagePercent,
            trendDirection: trendDirection
        )
    }
    
    private func generatePredictions(trends: CleanupAnalytics.CleanupTrends, diskGrowth: CleanupAnalytics.DiskSpaceGrowth) -> CleanupAnalytics.CleanupPredictions {
        let entries = historyManager.entries.sorted { $0.timestamp > $1.timestamp }
        
        // Predict next cleanup date based on average frequency
        let nextRecommendedCleanup: Date?
        if let lastCleanup = entries.first?.timestamp {
            let avgDaysBetween = calculateAverageDaysBetweenCleanups()
            nextRecommendedCleanup = Calendar.current.date(byAdding: .day, value: Int(avgDaysBetween), to: lastCleanup)
        } else {
            nextRecommendedCleanup = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        }
        
        // Estimate space available based on trends
        let estimatedSpaceAvailable = trends.averageSpaceFreedPerCleanup
        
        // High priority categories (frequently cleaned and high space)
        let categoryFreq = calculateCategoryFrequency()
        let highPriority = categoryFreq.prefix(3).map { $0.category }
        
        // Predict space that could be freed
        let predictedSpaceFreed = trends.averageSpaceFreedPerCleanup
        
        return CleanupAnalytics.CleanupPredictions(
            nextRecommendedCleanup: nextRecommendedCleanup,
            estimatedSpaceAvailable: estimatedSpaceAvailable,
            highPriorityCategories: highPriority,
            predictedSpaceFreed: predictedSpaceFreed
        )
    }
    
    private func calculateAverageDaysBetweenCleanups() -> Double {
        let entries = historyManager.entries.sorted { $0.timestamp < $1.timestamp }
        guard entries.count >= 2 else { return 7.0 }
        
        var totalDays = 0
        for i in 1..<entries.count {
            if let days = Calendar.current.dateComponents([.day], from: entries[i-1].timestamp, to: entries[i].timestamp).day {
                totalDays += days
            }
        }
        
        return Double(totalDays) / Double(entries.count - 1)
    }
}

