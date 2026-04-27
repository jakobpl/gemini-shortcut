//
//  OllamaProvider.swift
//  Local Ollama provider — talks to /api/chat with stream=true.
//

import Foundation
import AppKit

@MainActor
final class OllamaProvider: LLMProvider {
    static let shared = OllamaProvider()
    private init() {}

    let id: ProviderID = .ollama

    /// Static defaults — actual user-installed models may differ. The Settings
    /// "Test connection" button can populate the real list from /api/tags.
    let availableModels: [LLMModel] = [
        LLMModel(id: "gpt-oss:20b",       displayName: "GPT-OSS 20B (local)",     provider: .ollama, supportsImages: false),
        LLMModel(id: "deepseek-r1:32b",   displayName: "DeepSeek-R1 32B (local)", provider: .ollama, supportsImages: false),
        LLMModel(id: "llama3.3:70b",      displayName: "Llama 3.3 70B (local)",   provider: .ollama, supportsImages: false),
        LLMModel(id: "qwen3:32b",         displayName: "Qwen 3 32B (local)",      provider: .ollama, supportsImages: false),
    ]

    func streamResponse(
        messages: [ChatMessage],
        model: String,
        systemInstructions: String?
    ) async throws -> AsyncStream<String> {
        if SettingsManager.shared.isDevBypassEnabled {
            return GeminiProvider.devBypassStream()
        }

        let baseURL = SettingsManager.shared.ollamaBaseURL
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)api/chat" : "\(baseURL)/api/chat"
        guard let url = URL(string: endpoint) else { throw LLMError.invalidURL }

        // Window
        let meaningful = messages.filter { !$0.text.isEmpty }
        let windowed: [ChatMessage]
        if meaningful.count <= 6 {
            windowed = meaningful
        } else {
            let summaryText = meaningful.prefix(meaningful.count - 6)
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
                .joined(separator: "\n")
            let summary = ChatMessage(
                role: .user,
                text: "[Previous conversation context]\n\(summaryText)",
                images: [],
                isStreaming: false
            )
            windowed = [summary] + Array(meaningful.suffix(6))
        }

        var apiMessages: [[String: Any]] = []
        let sys = (systemInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for message in windowed {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncStream { continuation in
            Task { @MainActor in
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        var err = ""
                        for try await line in bytes.lines { err += line }
                        throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? 0, err)
                    }

                    // Ollama streams newline-delimited JSON (one object per line, no `data:` prefix).
                    for try await line in bytes.lines {
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let message = object["message"] as? [String: Any],
                           let content = message["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                        if let done = object["done"] as? Bool, done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                    continuation.finish()
                }
            }
        }
    }

    /// Probe Ollama for installed models. Used by Settings to verify the connection.
    static func listInstalledModels() async -> [String] {
        let baseURL = SettingsManager.shared.ollamaBaseURL
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)api/tags" : "\(baseURL)/api/tags"
        guard let url = URL(string: endpoint) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }
}
