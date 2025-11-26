import SwiftUI

struct FilePreviewView: View {
    @Environment(CleanupEngine.self) var cleanupEngine
    @Binding var cleanupItems: [CleanupItem]
    let selectedCategories: Set<CleanupCategoryType>
    
    @State private var selectedCategory: CleanupCategoryType?
    @State private var isLoading = false
    @State private var loadedFiles: [CleanupCategoryType: [CleanupFile]] = [:]
    
    private var categoriesToDisplay: [CleanupItem] {
        cleanupItems.filter { selectedCategories.contains($0.category) }
    }
    
    var body: some View {
        NavigationSplitView {
            List(categoriesToDisplay, selection: $selectedCategory) { item in
                NavigationLink(value: item.category) {
                    HStack {
                        Text(item.name)
                        Spacer()
                        if let files = item.files {
                            Text("\(files.count) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if loadedFiles[item.category] != nil {
                             Text("\(loadedFiles[item.category]?.count ?? 0) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Categories")
        } detail: {
            if let categoryType = selectedCategory,
               let itemIndex = cleanupItems.firstIndex(where: { $0.category == categoryType }) {
                FileListView(
                    item: $cleanupItems[itemIndex],
                    isLoading: isLoading,
                    onLoad: { loadFiles(for: categoryType) }
                )
            } else {
                Text("Select a category to view files")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = categoriesToDisplay.first?.category
            }
        }
    }
    
    private func loadFiles(for category: CleanupCategoryType) {
        // If already loaded in the item, don't reload
        if let index = cleanupItems.firstIndex(where: { $0.category == category }),
           cleanupItems[index].files != nil {
            return
        }
        
        // If already loaded locally, update item
        if let files = loadedFiles[category],
           let index = cleanupItems.firstIndex(where: { $0.category == category }) {
            cleanupItems[index].files = files
            return
        }
        
        isLoading = true
        Task {
            let files = await cleanupEngine.getDetailedFiles(for: category)
            
            await MainActor.run {
                loadedFiles[category] = files
                if let index = cleanupItems.firstIndex(where: { $0.category == category }) {
                    cleanupItems[index].files = files
                }
                isLoading = false
            }
        }
    }
}

struct FileListView: View {
    @Binding var item: CleanupItem
    let isLoading: Bool
    let onLoad: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(item.name)
                    .font(.headline)
                Spacer()
                if let files = item.files {
                    Text(ByteCountFormatter.string(fromByteCount: files.filter { !$0.isExcluded }.map { $0.size }.reduce(0, +), countStyle: .file))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            if isLoading {
                ProgressView("Loading files...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let files = item.files {
                if files.isEmpty {
                    Text("No files found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let filesBinding = Binding($item.files) {
                            ForEach(filesBinding) { $file in
                                FileRow(file: $file)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .onAppear(perform: onLoad)
            }
        }
    }
}

struct FileRow: View {
    @Binding var file: CleanupFile
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { !file.isExcluded },
                set: { file.isExcluded = !$0 }
            ))
            .labelsHidden()
            
            VStack(alignment: .leading) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
