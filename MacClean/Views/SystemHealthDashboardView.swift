import SwiftUI

struct SystemHealthDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(CleanupEngine.self) var cleanupEngine
    @State private var health: SystemHealth?
    @State private var isLoading = true
    private let healthManager: SystemHealthManager
    
    init(cleanupEngine: CleanupEngine) {
        self.healthManager = SystemHealthManager(cleanupEngine: cleanupEngine)
    }
    
    var body: some View {
        NavigationStack {
            if isLoading {
                ProgressView("Analyzing system health...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let health = health {
                ScrollView {
                    VStack(spacing: 20) {
                        // Health Score
                        HealthScoreSection(health: health)
                        
                        // Performance Metrics
                        PerformanceMetricsSection(metrics: health.performanceMetrics)
                        
                        // Recommendations
                        RecommendationsSection(recommendations: health.recommendations)
                        
                        // Maintenance Schedule
                        MaintenanceScheduleSection(schedule: health.maintenanceSchedule)
                    }
                    .padding()
                }
                .navigationTitle("System Health Dashboard")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            } else {
                VStack {
                    Text("Unable to load system health data")
                        .foregroundColor(.secondary)
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 800, height: 700)
        .onAppear {
            loadHealth()
        }
        .refreshable {
            loadHealth()
        }
    }
    
    private func loadHealth() {
        isLoading = true
        Task {
            let healthData = await healthManager.calculateHealth()
            await MainActor.run {
                health = healthData
                isLoading = false
            }
        }
    }
}

struct HealthScoreSection: View {
    let health: SystemHealth
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Overall Health Score")
                .font(.title2)
                .fontWeight(.bold)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: health.overallHealthScore)
                    .stroke(healthColor(health.overallHealthScore), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                
                VStack {
                    Text("\(Int(health.overallHealthScore * 100))")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(healthColor(health.overallHealthScore))
                    Text("out of 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 40) {
                VStack {
                    Text("Disk Health")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(health.diskHealthScore * 100))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(healthColor(health.diskHealthScore))
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func healthColor(_ score: Double) -> Color {
        if score >= 0.7 {
            return .green
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PerformanceMetricsSection: View {
    let metrics: SystemHealth.PerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Metrics")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 24) {
                MetricCard(
                    title: "Disk Usage",
                    value: "\(String(format: "%.1f", metrics.diskUsagePercent))%",
                    icon: "externaldrive.fill",
                    color: metrics.diskUsagePercent > 80 ? .red : metrics.diskUsagePercent > 60 ? .orange : .green
                )
                
                if let cpu = metrics.cpuUsagePercent {
                    MetricCard(
                        title: "CPU Usage",
                        value: "\(String(format: "%.1f", cpu))%",
                        icon: "cpu.fill",
                        color: cpu > 80 ? .red : cpu > 60 ? .orange : .green
                    )
                }
                
                if let memory = metrics.memoryUsagePercent {
                    MetricCard(
                        title: "Memory Usage",
                        value: "\(String(format: "%.1f", memory))%",
                        icon: "memorychip.fill",
                        color: memory > 80 ? .red : memory > 60 ? .orange : .green
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct RecommendationsSection: View {
    let recommendations: [SystemHealth.HealthRecommendation]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.title2)
                .fontWeight(.bold)
            
            if recommendations.isEmpty {
                Text("No recommendations at this time. Your system is healthy!")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                    RecommendationRow(recommendation: recommendation)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct RecommendationRow: View {
    let recommendation: SystemHealth.HealthRecommendation
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: priorityIcon(recommendation.priority))
                .foregroundColor(priorityColor(recommendation.priority))
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.message)
                    .font(.headline)
                
                Text(recommendation.estimatedImpact)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Action: \(recommendation.action)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func priorityIcon(_ priority: SystemHealth.HealthRecommendation.Priority) -> String {
        switch priority {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }
    
    private func priorityColor(_ priority: SystemHealth.HealthRecommendation.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

struct MaintenanceScheduleSection: View {
    let schedule: SystemHealth.MaintenanceSchedule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance Schedule")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 24) {
                if let lastCleanup = schedule.lastCleanup {
                    VStack(alignment: .leading) {
                        Text("Last Cleanup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastCleanup.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                    }
                }
                
                if let daysSince = schedule.daysSinceLastCleanup {
                    VStack(alignment: .leading) {
                        Text("Days Since")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(daysSince) days")
                            .font(.headline)
                            .foregroundColor(daysSince > 30 ? .orange : .green)
                    }
                }
                
                if let nextCleanup = schedule.nextRecommendedCleanup {
                    VStack(alignment: .leading) {
                        Text("Next Recommended")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(nextCleanup.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Frequency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Every \(schedule.recommendedFrequency) days")
                        .font(.headline)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

