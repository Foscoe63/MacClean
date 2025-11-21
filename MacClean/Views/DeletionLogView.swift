import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DeletionLogView: View {
    @Environment(\.dismiss) var dismiss
    @State private var logEntries: [DeletionLogEntry] = []
    @State private var filteredEntries: [DeletionLogEntry] = []
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTimeRange: TimeRange = .all
    @State private var showExportDialog = false
    @State private var isExporting = false
    
    enum TimeRange: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        
        var date: Date? {
            switch self {
            case .all: return nil
            case .today: return Calendar.current.startOfDay(for: Date())
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            }
        }
    }
    
    private var categories: [String] {
        Array(Set(logEntries.map { $0.category })).sorted()
    }
    
    private var totalSpaceFreed: Int64 {
        filteredEntries.filter { $0.success }.reduce(0) { $0 + $1.fileSize }
    }
    
    private var totalFilesDeleted: Int {
        filteredEntries.filter { $0.success }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            VStack(spacing: 12) {
                HStack {
                    Text("Deletion Log")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Export") {
                        // Export directly instead of using fileExporter
                        exportLogToFile()
                    }
                    .disabled(isExporting || filteredEntries.isEmpty)
                    
                    Button("Refresh") {
                        loadLogEntries()
                    }
                    
                    Button("Clear Log") {
                        DeletionLogManager.shared.clearLog()
                        loadLogEntries()
                    }
                    .foregroundColor(.red)
                    .disabled(logEntries.isEmpty)
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                
                HStack(spacing: 24) {
                    StatView(
                        title: "Files Deleted",
                        value: "\(totalFilesDeleted)",
                        icon: "doc.badge.minus"
                    )
                    
                    StatView(
                        title: "Space Freed",
                        value: ByteCountFormatter.string(fromByteCount: totalSpaceFreed, countStyle: .file),
                        icon: "externaldrive.badge.checkmark"
                    )
                    
                    StatView(
                        title: "Total Entries",
                        value: "\(filteredEntries.count)",
                        icon: "list.bullet"
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Filters
            VStack(spacing: 12) {
                HStack {
                    TextField("Search files...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as String?)
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category as String?)
                        }
                    }
                    .frame(width: 200)
                    
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .frame(width: 150)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Log entries list
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No deletion entries found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if !logEntries.isEmpty {
                        Text("Try adjusting your filters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Total entries: \(logEntries.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            Text("Deletion log will appear here after cleanup operations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Refresh") {
                                loadLogEntries()
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredEntries) {
                    TableColumn("Time") { entry in
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    .width(min: 150, ideal: 180)
                    
                    TableColumn("File Path") { entry in
                        Text(entry.filePath)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .width(min: 300)
                    
                    TableColumn("Category") { entry in
                        Text(entry.category)
                            .font(.caption)
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Size") { entry in
                        Text(ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Status") { entry in
                        HStack(spacing: 4) {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.success ? .green : .red)
                            Text(entry.success ? "Success" : "Failed")
                                .font(.caption)
                        }
                    }
                    .width(min: 100, ideal: 120)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            print("DeletionLogView appeared - loading entries...")
            loadLogEntries()
        }
        .refreshable {
            print("DeletionLogView refresh - reloading entries...")
            loadLogEntries()
        }
        .onChange(of: searchText) { _, _ in
            filterEntries()
        }
        .onChange(of: selectedCategory) { _, _ in
            filterEntries()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            filterEntries()
        }
        .fileExporter(
            isPresented: $showExportDialog,
            document: DeletionLogDocument(entries: filteredEntries),
            contentType: .json,
            defaultFilename: "deletion_log_\(Date().formatted(date: .numeric, time: .omitted))"
        ) { result in
            if case .success = result {
                isExporting = false
            }
        }
        .task {
            // Load entries when view appears
            loadLogEntries()
        }
    }
    
    private func loadLogEntries() {
        logEntries = DeletionLogManager.shared.getAllLogEntries()
        print("DeletionLogView: Loaded \(logEntries.count) log entries")
        filterEntries()
        print("DeletionLogView: Filtered to \(filteredEntries.count) entries")
    }
    
    private func filterEntries() {
        var filtered = logEntries
        
        // Filter by time range
        if let startDate = selectedTimeRange.date {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }
        
        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { entry in
                entry.filePath.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort by timestamp (newest first)
        filteredEntries = filtered.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func exportLogToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "deletion_log_\(Date().formatted(date: .numeric, time: .omitted)).json"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try DeletionLogManager.shared.exportLog(to: url)
                } catch {
                    print("Failed to export log: \(error)")
                }
            }
        }
    }
}

struct StatView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct DeletionLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var entries: [DeletionLogEntry]
    
    init(entries: [DeletionLogEntry]) {
        self.entries = entries
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.entries = try decoder.decode([DeletionLogEntry].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    DeletionLogView()
        .frame(width: 800, height: 600)
}

