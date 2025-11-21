import SwiftUI

struct FilePreviewView: View {
    let cleanupItems: [CleanupItem]
    let selectedCategories: Set<CleanupCategoryType>
    
    private var itemsToClean: [CleanupItem] {
        cleanupItems.filter { selectedCategories.contains($0.category) }
    }
    
    private var totalSize: Int64 {
        itemsToClean.compactMap { $0.estimatedSize }.reduce(0, +)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Text("\(itemsToClean.count) categories")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if itemsToClean.isEmpty {
                Text("No items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(itemsToClean) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                if let size = item.estimatedSize {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.vertical, 4)
                            
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 200)
                
                HStack {
                    Text("Total size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 300)
    }
}

