import SwiftUI

struct CleanupAnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var analytics: CleanupAnalytics?
    @State private var isLoading = true
    private let analyticsManager = CleanupAnalyticsManager.shared
    
    var body: some View {
        NavigationStack {
            if isLoading {
                ProgressView("Loading analytics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analytics = analytics {
                ScrollView {
                    VStack(spacing: 20) {
                        // Trends Section
                        TrendsSection(trends: analytics.trends)
                        
                        // Category Frequency
                        CategoryFrequencySection(categories: analytics.frequentlyCleanedCategories)
                        
                        // Disk Space Growth
                        DiskGrowthSection(growth: analytics.diskSpaceGrowth)
                        
                        // Predictions
                        PredictionsSection(predictions: analytics.predictions)
                    }
                    .padding()
                }
                .navigationTitle("Cleanup Analytics")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            } else {
                VStack {
                    Text("No analytics data available")
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
        .frame(width: 800, height: 600)
        .onAppear {
            loadAnalytics()
        }
    }
    
    private func loadAnalytics() {
        isLoading = true
        Task {
            let analyticsData = analyticsManager.generateAnalytics()
            await MainActor.run {
                analytics = analyticsData
                isLoading = false
            }
        }
    }
}

struct TrendsSection: View {
    let trends: CleanupAnalytics.CleanupTrends
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Trends")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("\(trends.totalCleanups)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Total Cleanups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text(ByteCountFormatter.string(fromByteCount: trends.averageSpaceFreedPerCleanup, countStyle: .file))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Avg Space Freed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Simple trend visualization
            if !trends.monthly.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly Trends")
                        .font(.headline)
                    
                    ForEach(Array(trends.monthly.keys.sorted().suffix(6)), id: \.self) { date in
                        HStack {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 20)
                                    
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(
                                            width: geometry.size.width * min(1.0, CGFloat(trends.monthly[date] ?? 0) / CGFloat(trends.averageSpaceFreedPerCleanup * 2)),
                                            height: 20
                                        )
                                }
                            }
                            .frame(height: 20)
                            
                            Text(ByteCountFormatter.string(fromByteCount: trends.monthly[date] ?? 0, countStyle: .file))
                                .font(.caption)
                                .frame(width: 80, alignment: .trailing)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct CategoryFrequencySection: View {
    let categories: [CleanupAnalytics.CategoryFrequency]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequently Cleaned Categories")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(Array(categories.prefix(5)), id: \.category) { category in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.category)
                            .font(.headline)
                        Text("\(category.cleanups) cleanups")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteCountFormatter.string(fromByteCount: category.totalSpaceFreed, countStyle: .file))
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("Avg: \(ByteCountFormatter.string(fromByteCount: category.averageSpaceFreed, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct DiskGrowthSection: View {
    let growth: CleanupAnalytics.DiskSpaceGrowth
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Space Growth")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Current Usage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", growth.currentUsagePercent))%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(growth.currentUsagePercent > 80 ? .red : growth.currentUsagePercent > 60 ? .orange : .green)
                }
                
                VStack(alignment: .leading) {
                    Text("Growth Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f GB/day", growth.growthRate))
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                if let projectedDate = growth.projectedFullDate {
                    VStack(alignment: .leading) {
                        Text("Projected Full")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text(projectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Trend indicator
            HStack {
                Image(systemName: growth.trendDirection == .increasing ? "arrow.up.circle.fill" : growth.trendDirection == .decreasing ? "arrow.down.circle.fill" : "minus.circle.fill")
                    .foregroundColor(growth.trendDirection == .increasing ? .red : growth.trendDirection == .decreasing ? .green : .gray)
                Text("Trend: \(growth.trendDirection == .increasing ? "Increasing" : growth.trendDirection == .decreasing ? "Decreasing" : "Stable")")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct PredictionsSection: View {
    let predictions: CleanupAnalytics.CleanupPredictions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Predictions")
                .font(.title2)
                .fontWeight(.bold)
            
            if let nextCleanup = predictions.nextRecommendedCleanup {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Next Recommended Cleanup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(nextCleanup.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Estimated Space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: predictions.estimatedSpaceAvailable, countStyle: .file))
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            if !predictions.highPriorityCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("High Priority Categories")
                        .font(.headline)
                    
                    ForEach(predictions.highPriorityCategories, id: \.self) { category in
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                            Text(category)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}


