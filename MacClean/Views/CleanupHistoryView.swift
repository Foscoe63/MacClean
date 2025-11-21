import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CleanupHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var historyManager: CleanupHistoryManager
    @State private var selectedPeriod: HistoryPeriod = .all
    
    enum HistoryPeriod: String, CaseIterable {
        case all = "All Time"
        case week = "Last Week"
        case month = "Last Month"
        
        var days: Int? {
            switch self {
            case .all: return nil
            case .week: return 7
            case .month: return 30
            }
        }
    }
    
    var filteredEntries: [CleanupHistoryEntry] {
        if let days = selectedPeriod.days {
            return historyManager.entriesForPeriod(days: days)
        } else {
            return historyManager.entries
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Statistics Header
                VStack(spacing: 16) {
                    HStack(spacing: 32) {
                        StatCard(
                            title: "Total Space Freed",
                            value: ByteCountFormatter.string(fromByteCount: historyManager.totalSpaceFreed, countStyle: .file),
                            color: .green
                        )
                        
                        StatCard(
                            title: "Total Items Deleted",
                            value: "\(historyManager.totalItemsDeleted)",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Cleanup Sessions",
                            value: "\(historyManager.entries.count)",
                            color: .orange
                        )
                    }
                    
                    if !historyManager.entries.isEmpty {
                        HStack(spacing: 16) {
                            StatCard(
                                title: "Weekly",
                                value: ByteCountFormatter.string(fromByteCount: historyManager.weeklyStats.spaceFreed, countStyle: .file),
                                color: .purple,
                                compact: true
                            )
                            
                            StatCard(
                                title: "Monthly",
                                value: ByteCountFormatter.string(fromByteCount: historyManager.monthlyStats.spaceFreed, countStyle: .file),
                                color: .pink,
                                compact: true
                            )
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Period Selector
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // History List
                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Cleanup History")
                            .font(.headline)
                        
                        Text("Your cleanup history will appear here after you clean your Mac.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Cleanup History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export as CSV") {
                            exportHistory()
                        }
                        
                        if !historyManager.entries.isEmpty {
                            Divider()
                            
                            Button("Clear History", role: .destructive) {
                                historyManager.clearHistory()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .frame(width: 800, height: 600)
        }
    }
    
    private func exportHistory() {
        let csv = historyManager.exportHistory()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "MacClean_History_\(Date().formatted(date: .numeric, time: .omitted)).csv"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    var compact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(compact ? .subheadline : .title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

struct HistoryEntryRow: View {
    let entry: CleanupHistoryEntry
    
    var body: some View {
        HStack {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(entry.success ? .green : .red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(entry.categories.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.formattedSpaceFreed)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                
                Text("\(entry.itemsDeleted) items • \(entry.formattedDuration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CleanupHistoryView(historyManager: CleanupHistoryManager())
}

