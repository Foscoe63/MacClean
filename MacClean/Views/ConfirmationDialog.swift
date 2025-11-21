import SwiftUI

struct CleanupConfirmationDialog: View {
    let categories: Set<CleanupCategoryType>
    let items: [CleanupItem]
    let totalSpace: Int64
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Confirm Cleanup")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("You are about to clean the following categories:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(categories), id: \.self) { category in
                        if let item = items.first(where: { $0.category == category }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    if let size = item.estimatedSize {
                                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Space to Free")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(categories.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                
                Button("Clean", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

