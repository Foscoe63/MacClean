import SwiftUI
import AppKit

/// Lists the largest files in the home folder so the user can review them and move chosen ones to the Trash.
struct LargeFilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var finder = LargeFileFinder()
    @State private var minimumSize: Int64 = 500_000_000
    @State private var selection = Set<LargeFile.ID>()
    @State private var showTrashConfirmation = false
    @State private var resultMessage: String?
    @State private var scanTask: Task<Void, Never>?
    
    private let sizeOptions: [Int64] = [100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]
    
    private var selectedFiles: [LargeFile] {
        finder.largeFiles.filter { selection.contains($0.id) }
    }
    
    private var selectedSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .onDisappear { scanTask?.cancel() }
        .confirmationDialog(
            "Move \(selectedFiles.count) files to the Trash?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: moveSelectionToTrash)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)) will be moved to the Trash. You can put them back from the Trash until it is emptied.")
        }
    }
    
    private var header: some View {
        HStack {
            Text("Large Files")
                .font(.title)
                .fontWeight(.bold)
            
            Spacer()
            
            Picker("Larger than", selection: $minimumSize) {
                ForEach(sizeOptions, id: \.self) { size in
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).tag(size)
                }
            }
            .frame(width: 200)
            
            Button(finder.isScanning ? "Scanning..." : "Scan Home Folder", action: startScan)
                .buttonStyle(.borderedProminent)
                .disabled(finder.isScanning)
            
            Button("Close") { dismiss() }
        }
        .padding()
    }
    
    @ViewBuilder
    private var content: some View {
        if finder.isScanning {
            ProgressView(finder.currentStatus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if finder.largeFiles.isEmpty {
            ContentUnavailableView(
                finder.currentStatus.isEmpty ? "No Scan Yet" : finder.currentStatus,
                systemImage: "doc.text.magnifyingglass",
                description: Text("Scan your home folder to list files above the chosen size.")
            )
        } else {
            Table(finder.largeFiles, selection: $selection) {
                TableColumn("Name") { file in
                    Text(file.fileName)
                        .help(file.path.path)
                }
                TableColumn("Folder") { file in
                    Text(file.path.deletingLastPathComponent().path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("Size") { file in
                    Text(file.formattedSize)
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 90)
                TableColumn("Modified") { file in
                    Text(file.modifiedDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                }
                .width(min: 90, ideal: 110)
            }
            .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
                Button("Reveal in Finder") { reveal(ids) }
                Button("Open") { reveal(ids, open: true) }
            } primaryAction: { ids in
                reveal(ids)
            }
        }
    }
    
    private var footer: some View {
        HStack {
            if let resultMessage {
                Text(resultMessage)
                    .foregroundStyle(.secondary)
            } else if !finder.largeFiles.isEmpty {
                Text("\(finder.largeFiles.count) files · double-click to reveal in Finder")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !selection.isEmpty {
                Text("\(selection.count) selected · \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
            }
            
            Button("Move to Trash") { showTrashConfirmation = true }
                .disabled(selection.isEmpty || finder.isScanning)
        }
        .padding()
    }
    
    private func startScan() {
        selection.removeAll()
        resultMessage = nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let minimumSize = minimumSize
        scanTask = Task {
            await finder.findLargeFiles(in: [home], minSize: minimumSize)
        }
    }
    
    private func moveSelectionToTrash() {
        let files = selectedFiles
        Task {
            let result = await finder.moveToTrash(files)
            selection.removeAll()
            let failed = files.count - result.moved
            resultMessage = "Moved \(result.moved) files (\(ByteCountFormatter.string(fromByteCount: result.size, countStyle: .file))) to the Trash"
                + (failed > 0 ? ". \(failed) could not be moved." : ".")
        }
    }
    
    private func reveal(_ ids: Set<LargeFile.ID>, open: Bool = false) {
        let urls = finder.largeFiles.filter { ids.contains($0.id) }.map(\.path)
        guard !urls.isEmpty else { return }
        if open, let first = urls.first {
            NSWorkspace.shared.open(first)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

#Preview {
    LargeFilesView()
}
