import SwiftUI
import Charts

struct DiskUsageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVolume: URL?
    @State private var volumes: [URL] = []
    @State private var diskInfo: DiskInfo?
    @State private var categoryBreakdown: [CategoryUsage] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack {
                Text("Disk Usage")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Volume picker
            if !volumes.isEmpty {
                HStack {
                    Text("Drive:")
                        .font(.headline)
                    Picker("", selection: $selectedVolume) {
                        ForEach(volumes, id: \.self) { url in
                            Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                                .tag(url as URL?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 200)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Overall Disk Usage
                    if let disk = diskInfo {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Disk Usage")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            // Circular progress
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                                
                                Circle()
                                    .trim(from: 0, to: disk.usedPercentage)
                                    .stroke(
                                        disk.usedPercentage > 0.9 ? Color.red :
                                        disk.usedPercentage > 0.7 ? Color.orange : Color.blue,
                                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                
                                VStack {
                                    Text("\(Int(disk.usedPercentage * 100))%")
                                        .font(.system(size: 36, weight: .bold))
                                    Text("Used")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 200, height: 200)
                            .frame(maxWidth: .infinity)
                            
                            // Stats
                            HStack(spacing: 40) {
                                VStack(alignment: .leading) {
                                    Text("Used")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(disk.usedFormatted)
                                        .font(.headline)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(disk.availableFormatted)
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Total")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(disk.totalFormatted)
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    
                    // Category Breakdown
                    if !categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Storage by Category")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Chart(categoryBreakdown) { item in
                                BarMark(
                                    x: .value("Size", item.size),
                                    y: .value("Category", item.name)
                                )
                                .foregroundStyle(item.color)
                            }
                            .frame(height: 300)
                            
                            VStack(spacing: 8) {
                                ForEach(categoryBreakdown) { item in
                                    HStack {
                                        Circle()
                                            .fill(item.color)
                                            .frame(width: 12, height: 12)
                                        Text(item.name)
                                            .font(.subheadline)
                                        Spacer()
                                        Text(item.sizeFormatted)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    
                    if isLoading {
                        ProgressView("Analyzing disk usage...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            // Populate volumes list
            let fm = FileManager.default
            if let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey], options: []) {
                // Filter out system volumes
                let filteredVolumes = urls.filter { url in
                    let name = url.lastPathComponent.lowercased()
                    // Exclude system volumes
                    let systemVolumes = ["preboot", "recovery", "vm", "update", "xarts", "hardware", "isp support", "data"]
                    if systemVolumes.contains(name) {
                        return false
                    }
                    // Only include local volumes
                    if let resourceValues = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey]),
                       let isLocal = resourceValues.volumeIsLocal {
                        return isLocal
                    }
                    return true
                }
                self.volumes = filteredVolumes
                // Default to the first volume (usually the system drive)
                self.selectedVolume = filteredVolumes.first
            }
            loadDiskInfo()
        }
        .onChange(of: selectedVolume) {
            loadDiskInfo()
        }
    }
    
    private func loadDiskInfo() {
        guard let volume = selectedVolume else {
            print("DEBUG: No volume selected")
            return
        }
        print("DEBUG: Loading disk info for volume: \(volume.path)")
        isLoading = true
        Task {
            let info = await DiskAnalyzer.getDiskInfo(at: volume)
            print("DEBUG: Got disk info: \(String(describing: info))")
            let breakdown = await DiskAnalyzer.getCategoryBreakdown(at: volume)
            print("DEBUG: Got breakdown with \(breakdown.count) categories")
            await MainActor.run {
                diskInfo = info
                categoryBreakdown = breakdown
                isLoading = false
                print("DEBUG: Updated UI - diskInfo: \(String(describing: diskInfo)), categories: \(categoryBreakdown.count)")
            }
        }
    }
}

struct DiskInfo {
    let total: Int64
    let used: Int64
    let available: Int64
    
    var usedPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }
    
    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }
    var availableFormatted: String {
        ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }
}

struct CategoryUsage: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let color: Color
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

actor DiskAnalyzer {
    static func getDiskInfo(at url: URL) async -> DiskInfo? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            let used = total - available
            return DiskInfo(total: total, used: used, available: available)
        } catch {
            print("Error getting disk info for \(url.path): \(error)")
            return nil
        }
    }
    
    @MainActor
    static func getCategoryBreakdown(at root: URL) async -> [CategoryUsage] {
        let fileManager = FileManager.default
        var breakdown: [CategoryUsage] = []
        
        // If this is the system volume, scan user directories
        let homeURL = fileManager.homeDirectoryForCurrentUser
        if root.path.hasPrefix("/") && !root.path.contains("/Volumes/") {
            // System volume - scan user directories
            let directories: [(String, String, Color)] = [
                ("Documents", "Documents", .blue),
                ("Downloads", "Downloads", .orange),
                ("Desktop", "Desktop", .green),
                ("Pictures", "Pictures", .purple),
                ("Movies", "Movies", .red),
                ("Music", "Music", .pink),
                ("Library/Caches", "Caches", .yellow),
                ("Library/Application Support", "App Data", .cyan)
            ]
            for (path, name, color) in directories {
                let url = homeURL.appendingPathComponent(path)
                let size = fileManager.sizeOfDirectory(at: url)
                if size > 0 {
                    breakdown.append(CategoryUsage(name: name, size: size, color: color))
                }
            }
        } else {
            // External volume - scan top-level directories
            do {
                let contents = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                for url in contents {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        let size = fileManager.sizeOfDirectory(at: url)
                        if size > 0 {
                            let name = url.lastPathComponent
                            let color = colorForDirectory(name)
                            breakdown.append(CategoryUsage(name: name, size: size, color: color))
                        }
                    }
                }
            } catch {
                print("Error scanning volume: \(error)")
            }
        }
        
        return breakdown.sorted { $0.size > $1.size }
    }
    
    private static func colorForDirectory(_ name: String) -> Color {
        switch name.lowercased() {
        case "documents": return .blue
        case "downloads": return .orange
        case "desktop": return .green
        case "pictures", "photos": return .purple
        case "movies", "videos": return .red
        case "music": return .pink
        case "applications": return .cyan
        case "library": return .yellow
        default: return .gray
        }
    }
}

#Preview {
    DiskUsageView()
}
