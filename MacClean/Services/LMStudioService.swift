import Foundation

struct LMStudioService: AIServiceProtocol {
    let endpoint: String
    let model: String
    let serviceType: AIServiceType = .lmStudio
    
    init(endpoint: String = "http://localhost:1234/v1", model: String = "") {
        self.endpoint = endpoint
        self.model = model
    }
    
    /// Tests the connection to LM Studio by checking if the server is reachable
    func testConnection() async throws {
        // Normalize and construct the models endpoint URL
        let modelsURL = try buildModelsURL()
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0 // 5 second timeout
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.requestFailed
            }
            
            // Accept any 2xx or 3xx response as success (server is reachable)
            if !(200...399).contains(httpResponse.statusCode) {
                throw AIServiceError.requestFailed
            }
        } catch let urlError as URLError {
            // Map common URL errors to more user-friendly messages
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                throw AIServiceError.connectionRefused
            case .timedOut:
                throw AIServiceError.connectionTimeout
            case .notConnectedToInternet:
                throw AIServiceError.noInternetConnection
            default:
                throw AIServiceError.requestFailed
            }
        }
    }
    
    /// Builds the /v1/models URL from the endpoint
    private func buildModelsURL() throws -> URL {
        var endpointString = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing slash
        if endpointString.hasSuffix("/") {
            endpointString = String(endpointString.dropLast())
        }
        
        guard let endpointURL = URL(string: endpointString) else {
            throw AIServiceError.invalidURL
        }
        
        // Get the base URL (scheme + host + port)
        guard let scheme = endpointURL.scheme,
              let host = endpointURL.host else {
            throw AIServiceError.invalidURL
        }
        
        let port = endpointURL.port
        var baseURLString = "\(scheme)://\(host)"
        if let port = port {
            baseURLString += ":\(port)"
        }
        
        guard let baseURL = URL(string: baseURLString) else {
            throw AIServiceError.invalidURL
        }
        
        // Always construct /v1/models from the base URL
        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("models")
    }
    
    /// Builds the /v1/chat/completions URL from the endpoint
    private func buildChatCompletionsURL() throws -> URL {
        var endpointString = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing slash
        if endpointString.hasSuffix("/") {
            endpointString = String(endpointString.dropLast())
        }
        
        guard let endpointURL = URL(string: endpointString) else {
            throw AIServiceError.invalidURL
        }
        
        // Get the base URL (scheme + host + port)
        guard let scheme = endpointURL.scheme,
              let host = endpointURL.host else {
            throw AIServiceError.invalidURL
        }
        
        let port = endpointURL.port
        var baseURLString = "\(scheme)://\(host)"
        if let port = port {
            baseURLString += ":\(port)"
        }
        
        guard let baseURL = URL(string: baseURLString) else {
            throw AIServiceError.invalidURL
        }
        
        // Always construct /v1/chat/completions from the base URL
        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }
    
    func sendChatMessage(_ message: String, context: ChatContext?) async throws -> String {
        let url = try buildChatCompletionsURL()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0
        
        // Build messages array with conversation history
        var messages: [[String: Any]] = []
        
        // Add system message with context
        var systemContent = "You are a helpful assistant for macOS system management and file cleanup. You can help users understand their system, find files, and make cleanup recommendations."
        if let context = context, let fsInfo = context.fileSystemInfo {
            systemContent += "\n\nSystem Information:\n"
            systemContent += "- Total Disk Space: \(ByteCountFormatter.string(fromByteCount: fsInfo.totalDiskSpace, countStyle: .file))\n"
            systemContent += "- Available Space: \(ByteCountFormatter.string(fromByteCount: fsInfo.availableDiskSpace, countStyle: .file))\n"
            if !fsInfo.homeDirectoryContents.isEmpty {
                systemContent += "- Home Directory Contents: \(fsInfo.homeDirectoryContents.prefix(20).joined(separator: ", "))\n"
            }
            if !fsInfo.recentFiles.isEmpty {
                systemContent += "- Recent Files: \(fsInfo.recentFiles.prefix(10).joined(separator: ", "))\n"
            }
        }
        
        messages.append([
            "role": "system",
            "content": systemContent
        ])
        
        // Add conversation history
        if let context = context {
            for chatMessage in context.conversationHistory.suffix(10) { // Keep last 10 messages
                messages.append([
                    "role": chatMessage.role == .user ? "user" : "assistant",
                    "content": chatMessage.content
                ])
            }
        }
        
        // Add current user message
        messages.append([
            "role": "user",
            "content": message
        ])
        
        let requestBody: [String: Any] = [
            "model": model.isEmpty ? "local-model" : model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.requestFailed
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed
        }
        
        let decoder = JSONDecoder()
        let lmResponse = try decoder.decode(LMStudioResponse.self, from: data)
        
        guard let content = lmResponse.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }
        
        return content
    }
    
    func getSuggestions(for items: [CleanupItem]) async throws -> [AISuggestion] {
        // Use the same URL construction as sendChatMessage
        let url = try buildChatCompletionsURL()
        
        let prompt = buildPrompt(for: items)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0 // Add timeout like sendChatMessage
        
        let requestBody: [String: Any] = [
            "model": model.isEmpty ? "local-model" : model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a helpful assistant that analyzes macOS cleanup opportunities. Provide suggestions in JSON format with category, reason, estimated space, and confidence (0.0-1.0)."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.requestFailed
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed
        }
        
        // Safely decode the response
        let decoder = JSONDecoder()
        let lmResponse: LMStudioResponse
        do {
            lmResponse = try decoder.decode(LMStudioResponse.self, from: data)
        } catch {
            // If decoding fails, try to get error details
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Failed to decode LM Studio response. Response was: \(jsonString)")
            }
            throw AIServiceError.parsingFailed
        }
        
        return parseSuggestions(from: lmResponse, items: items)
    }
    
    private func buildPrompt(for items: [CleanupItem]) -> String {
        var prompt = "Analyze these macOS cleanup categories and suggest which ones should be cleaned:\n\n"
        
        for item in items {
            let sizeStr = item.estimatedSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unknown"
            prompt += "- \(item.name): \(item.description) (Size: \(sizeStr))\n"
        }
        
        prompt += "\nProvide suggestions in this JSON format:\n"
        prompt += "[{\"category\": \"category_name\", \"reason\": \"why to clean\", \"estimatedSpace\": 123456, \"confidence\": 0.8}]"
        
        return prompt
    }
    
    private func parseSuggestions(from response: LMStudioResponse, items: [CleanupItem]) -> [AISuggestion] {
        guard let content = response.choices.first?.message.content else {
            return fallbackSuggestions(for: items)
        }
        
        // Try to extract JSON from the response
        var suggestions: [AISuggestion] = []
        
        // Look for JSON array in the response
        if let jsonData = extractJSON(from: content) {
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
                
                if let jsonArray = jsonObject as? [[String: Any]] {
                    // Array of objects
                    for json in jsonArray {
                        if let suggestion = parseSuggestion(from: json) {
                            suggestions.append(suggestion)
                        }
                    }
                } else if let jsonDict = jsonObject as? [String: Any] {
                    // Single object
                    if let suggestion = parseSuggestion(from: jsonDict) {
                        suggestions.append(suggestion)
                    }
                }
            } catch {
                // JSON parsing failed, fall through to fallback
                print("Failed to parse JSON from AI response: \(error)")
            }
        }
        
        // If no suggestions were parsed from JSON, use fallback
        if suggestions.isEmpty {
            return fallbackSuggestions(for: items)
        }
        
        return suggestions
    }
    
    private func parseSuggestion(from json: [String: Any]) -> AISuggestion? {
        guard let categoryStr = json["category"] as? String,
              let category = CleanupCategoryType.allCases.first(where: { $0.rawValue == categoryStr }),
              let reason = json["reason"] as? String else {
            return nil
        }
        
        let estimatedSpace = json["estimatedSpace"] as? Int64
        let confidence = (json["confidence"] as? Double) ?? 0.5
        
        return AISuggestion(
            category: category,
            reason: reason,
            estimatedSpace: estimatedSpace,
            confidence: confidence
        )
    }
    
    private func fallbackSuggestions(for items: [CleanupItem]) -> [AISuggestion] {
        var suggestions: [AISuggestion] = []
        
        // Fallback: create suggestions based on large items
        for item in items.sorted(by: { ($0.estimatedSize ?? 0) > ($1.estimatedSize ?? 0) }).prefix(3) {
            if let size = item.estimatedSize, size > 100_000_000 { // > 100MB
                let suggestion = AISuggestion(
                    category: item.category,
                    reason: "Large cache files detected that can be safely removed",
                    estimatedSpace: size,
                    confidence: 0.7
                )
                suggestions.append(suggestion)
            }
        }
        
        return suggestions
    }
    
    private func extractJSON(from text: String) -> Data? {
        // Try to find JSON array in the text
        guard let startIndex = text.firstIndex(of: "["),
              let endIndex = text.lastIndex(of: "]"),
              startIndex < endIndex else {
            return nil
        }
        
        // Safely extract the substring
        let jsonString = String(text[startIndex...endIndex])
        return jsonString.data(using: .utf8)
    }
}

struct LMStudioResponse: Codable {
    let choices: [LMStudioChoice]
    
    struct LMStudioChoice: Codable {
        let message: LMStudioMessage
    }
    
    struct LMStudioMessage: Codable {
        let content: String
    }
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case requestFailed
    case invalidResponse
    case parsingFailed
    case connectionRefused
    case connectionTimeout
    case noInternetConnection
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API endpoint URL"
        case .requestFailed:
            return "Failed to connect to AI service"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .parsingFailed:
            return "Failed to parse AI response"
        case .connectionRefused:
            return "Connection refused. Please ensure LM Studio is running and the API server is started on the specified port."
        case .connectionTimeout:
            return "Connection timed out. The server may be slow to respond or unreachable."
        case .noInternetConnection:
            return "No internet connection available"
        }
    }
}

