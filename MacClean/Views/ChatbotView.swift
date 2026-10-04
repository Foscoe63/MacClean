import SwiftUI

struct ChatbotView: View {
    @Environment(PreferencesManager.self) var preferencesManager
    @Environment(\.dismiss) var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var fileSystemInfo: ChatContext.FileSystemInfo?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "message.fill")
                    .foregroundColor(.blue)
                Text("AI Chatbot")
                    .font(.headline)
                
                Spacer()
                
                Text(preferencesManager.preferences.aiServiceType == .lmStudio ? "LM Studio" : "Apple Intelligence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 48))
                                    .foregroundColor(.blue)
                                
                                Text("Ask me anything about your Mac")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                
                                Text("I can help you with:\n• Disk space and storage\n• Finding files\n• Cleanup recommendations\n• System maintenance")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                TextField("Type your message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isSending)
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 500)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            // Load file system info on appear
            fileSystemInfo = await FileSystemInfoHelper.gatherFileSystemInfo()
        }
    }
    
    private func sendMessage() {
        let trimmedMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !isSending else { return }
        
        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            content: trimmedMessage,
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""
        
        // Send to AI service
        isSending = true
        Task {
            do {
                let service = AIServiceFactory.createService(
                    for: preferencesManager.preferences.aiServiceType,
                    preferences: preferencesManager.preferences
                )
                
                // Build context with file system info and conversation history
                let context = ChatContext(
                    fileSystemInfo: fileSystemInfo,
                    enhancedContext: nil, // Can be enhanced later if needed
                    conversationHistory: messages
                )
                
                let response = try await service.sendChatMessage(trimmedMessage, context: context)
                
                await MainActor.run {
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: response,
                        timestamp: Date()
                    )
                    messages.append(assistantMessage)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to send message: \(error.localizedDescription)"
                    showError = true
                    isSending = false
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user 
                                  ? Color.blue 
                                  : Color(NSColor.controlBackgroundColor))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

#Preview {
    ChatbotView()
        .environment(PreferencesManager())
}

