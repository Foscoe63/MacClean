import SwiftUI

struct CleanupProgressView: View {
    let progress: Double
    let status: String
    let showPercentage: Bool
    
    init(progress: Double, status: String, showPercentage: Bool = true) {
        self.progress = progress
        self.status = status
        self.showPercentage = showPercentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    CleanupProgressView(
        progress: 0.65,
        status: "Cleaning User Caches..."
    )
    .padding()
    .frame(width: 400)
}

