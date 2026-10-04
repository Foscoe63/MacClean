import Foundation

struct SystemHealth {
    let diskHealthScore: Double // 0.0 to 1.0
    let overallHealthScore: Double // 0.0 to 1.0
    let recommendations: [HealthRecommendation]
    let performanceMetrics: PerformanceMetrics
    let maintenanceSchedule: MaintenanceSchedule
    
    struct HealthRecommendation {
        let priority: Priority
        let category: String
        let message: String
        let estimatedImpact: String
        let action: String
        
        enum Priority {
            case high
            case medium
            case low
        }
    }
    
    struct PerformanceMetrics {
        let diskUsagePercent: Double
        let cpuUsagePercent: Double?
        let memoryUsagePercent: Double?
        let diskReadSpeed: Double? // MB/s
        let diskWriteSpeed: Double? // MB/s
    }
    
    struct MaintenanceSchedule {
        let lastCleanup: Date?
        let nextRecommendedCleanup: Date?
        let daysSinceLastCleanup: Int?
        let recommendedFrequency: Int // days
    }
}

@Observable
class SystemHealthManager {
    private let cleanupEngine: CleanupEngine
    private let historyManager = CleanupHistoryManager.shared
    private let analyticsManager = CleanupAnalyticsManager.shared
    
    init(cleanupEngine: CleanupEngine) {
        self.cleanupEngine = cleanupEngine
    }
    
    func calculateHealth() async -> SystemHealth {
        let diskHealth = await calculateDiskHealthScore()
        let performance = await gatherPerformanceMetrics()
        let recommendations = generateRecommendations(diskHealth: diskHealth, performance: performance)
        let maintenance = calculateMaintenanceSchedule()
        let overallHealth = calculateOverallHealth(diskHealth: diskHealth, performance: performance)
        
        return SystemHealth(
            diskHealthScore: diskHealth,
            overallHealthScore: overallHealth,
            recommendations: recommendations,
            performanceMetrics: performance,
            maintenanceSchedule: maintenance
        )
    }
    
    private func calculateDiskHealthScore() async -> Double {
        guard let diskSpace = DiskSpace.current(), case let (total, free) = (diskSpace.total, diskSpace.available) else {
            return 0.5
        }
        
        let used = total - free
        let usagePercent = Double(used) / Double(total)
        
        // Score based on available space (more free = higher score)
        let freePercent = 1.0 - usagePercent
        
        // Factor in cleanup history (recent cleanups = better score)
        let entries = historyManager.entries
        let recentCleanups = entries.filter { Calendar.current.dateComponents([.day], from: $0.timestamp, to: Date()).day ?? 0 < 30 }
        let cleanupScore = min(1.0, Double(recentCleanups.count) / 4.0) // Max score at 4+ cleanups in 30 days
        
        // Combine scores
        return (freePercent * 0.7) + (cleanupScore * 0.3)
    }
    
    private func gatherPerformanceMetrics() async -> SystemHealth.PerformanceMetrics {
        var diskUsagePercent: Double = 0
        
        if let diskSpace = DiskSpace.current(), case let (total, free) = (diskSpace.total, diskSpace.available) {
            let used = total - free
            diskUsagePercent = Double(used) / Double(total) * 100
        }
        
        // Note: CPU and memory usage would require additional system APIs
        // For now, we'll leave them as nil
        let cpuUsage: Double? = nil
        let memoryUsage: Double? = nil
        
        return SystemHealth.PerformanceMetrics(
            diskUsagePercent: diskUsagePercent,
            cpuUsagePercent: cpuUsage,
            memoryUsagePercent: memoryUsage,
            diskReadSpeed: nil,
            diskWriteSpeed: nil
        )
    }
    
    private func generateRecommendations(diskHealth: Double, performance: SystemHealth.PerformanceMetrics) -> [SystemHealth.HealthRecommendation] {
        var recommendations: [SystemHealth.HealthRecommendation] = []
        
        // Disk space recommendations
        if performance.diskUsagePercent > 90 {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .high,
                category: "Disk Space",
                message: "Disk is critically full (\(String(format: "%.1f", performance.diskUsagePercent))% used)",
                estimatedImpact: "Free up space immediately to prevent system issues",
                action: "Run full cleanup now"
            ))
        } else if performance.diskUsagePercent > 80 {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .high,
                category: "Disk Space",
                message: "Disk is getting full (\(String(format: "%.1f", performance.diskUsagePercent))% used)",
                estimatedImpact: "Free up space soon to maintain performance",
                action: "Run cleanup in the next few days"
            ))
        } else if performance.diskUsagePercent > 60 {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .medium,
                category: "Disk Space",
                message: "Disk usage is moderate (\(String(format: "%.1f", performance.diskUsagePercent))% used)",
                estimatedImpact: "Regular cleanup recommended",
                action: "Schedule weekly cleanup"
            ))
        }
        
        // Cleanup frequency recommendations
        let entries = historyManager.entries
        if entries.isEmpty {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .medium,
                category: "Maintenance",
                message: "No cleanup history found",
                estimatedImpact: "Start regular maintenance to keep system healthy",
                action: "Run your first cleanup"
            ))
        } else {
            let lastCleanup = entries.first?.timestamp
            if let last = lastCleanup {
                let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
                if daysSince > 30 {
                    recommendations.append(SystemHealth.HealthRecommendation(
                        priority: .medium,
                        category: "Maintenance",
                        message: "Last cleanup was \(daysSince) days ago",
                        estimatedImpact: "Regular cleanup improves system performance",
                        action: "Run cleanup now"
                    ))
                }
            }
        }
        
        // Health score recommendations
        if diskHealth < 0.3 {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .high,
                category: "System Health",
                message: "System health score is low",
                estimatedImpact: "Immediate action recommended",
                action: "Run comprehensive cleanup"
            ))
        } else if diskHealth < 0.6 {
            recommendations.append(SystemHealth.HealthRecommendation(
                priority: .medium,
                category: "System Health",
                message: "System health could be improved",
                estimatedImpact: "Regular maintenance will improve health",
                action: "Schedule regular cleanups"
            ))
        }
        
        return recommendations
    }
    
    private func calculateMaintenanceSchedule() -> SystemHealth.MaintenanceSchedule {
        let entries = historyManager.entries.sorted { $0.timestamp > $1.timestamp }
        let lastCleanup = entries.first?.timestamp
        
        let daysSince: Int?
        if let last = lastCleanup {
            daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day
        } else {
            daysSince = nil
        }
        
        // Calculate recommended frequency based on usage patterns
        let recommendedFrequency: Int
        if entries.count >= 3 {
            let avgDays = analyticsManager.generateAnalytics().predictions.nextRecommendedCleanup.map { date in
                Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 7
            } ?? 7
            recommendedFrequency = max(3, min(30, Int(avgDays)))
        } else {
            recommendedFrequency = 7 // Default to weekly
        }
        
        let nextRecommended: Date?
        if let last = lastCleanup {
            nextRecommended = Calendar.current.date(byAdding: .day, value: recommendedFrequency, to: last)
        } else {
            nextRecommended = Calendar.current.date(byAdding: .day, value: recommendedFrequency, to: Date())
        }
        
        return SystemHealth.MaintenanceSchedule(
            lastCleanup: lastCleanup,
            nextRecommendedCleanup: nextRecommended,
            daysSinceLastCleanup: daysSince,
            recommendedFrequency: recommendedFrequency
        )
    }
    
    private func calculateOverallHealth(diskHealth: Double, performance: SystemHealth.PerformanceMetrics) -> Double {
        // Combine disk health with performance metrics
        var score = diskHealth
        
        // Adjust based on disk usage
        if performance.diskUsagePercent > 90 {
            score *= 0.5
        } else if performance.diskUsagePercent > 80 {
            score *= 0.7
        } else if performance.diskUsagePercent > 60 {
            score *= 0.9
        }
        
        return min(1.0, max(0.0, score))
    }
}

