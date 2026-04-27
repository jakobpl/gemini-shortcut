//
//  AnthropicProvider.swift
//  Anthropic Messages API streaming client.
//

import Foundation
import AppKit

@MainActor
final class AnthropicProvider: LLMProvider {
    static let shared = AnthropicProvider()
    private init() {}

    let id: ProviderID = .anthropic

    let availableModels: [LLMModel] = [
        LLMModel(id: "claude-opus-4-7",       displayName: "Claude Opus 4.7",   provider: .anthropic, supportsImages: true),
        LLMModel(id: "claude-sonnet-4-6",     displayName: "Claude Sonnet 4.6", provider: .anthropic, supportsImages: true),
        LLMModel(id: "claude-haiku-4-5",      displayName: "Claude Haiku 4.5",  provider: .anthropic, supportsImages: true),
    ]

    func streamResponse(
        messages: [ChatMessage],
        model: String,
        systemInstructions: String?
    ) async throws -> AsyncStream<String> {
        if SettingsManager.shared.isDevBypassEnabled {
            return GeminiProvider.devBypassStream()
        }

        guard let apiKey = SettingsManager.shared.apiKey(for: .anthropic), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(.anthropic)
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMError.invalidURL
        }

        // Window
        let meaningful = messages.filter { !$0.text.isEmpty || !$0.images.isEmpty }
        let windowed: [ChatMessage]
        if meaningful.count <= 6 {
            windowed = meaningful
        } else {
            let summaryText = meaningful.prefix(meaningful.count - 6)
                .map { "\($0.role == .user ? "Human" : "Assistant"): \($0.text)" }
                .joined(separator: "\n")
            let summary = ChatMessage(
                role: .user,
                text: "[Previous conversation context]\n\(summaryText)",
                images: [],
                isStreaming: false
            )
            windowed = [summary] + Array(meaningful.suffix(6))
        }

        // Anthropic message blocks
        var apiMessages: [[String: Any]] = []
        for message in windowed {
            let role = message.role == .user ? "user" : "assistant"
            var content: [[String: Any]] = []
            for image in message.images {
                if let pngData = ScreenshotService.pngData(from: image) {
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/png",
                            "data": pngData.base64EncodedString()
                        ]
                    ])
                }
            }
            if !message.text.isEmpty {
                content.append(["type": "text", "text": message.text])
            }
            guard !content.isEmpty else { continue }
            apiMessages.append(["role": role, "content": content])
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "messages": apiMessages
        ]
        let sys = (systemInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            body["system"] = sys
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        // We only care about content_block_delta events with text deltas
                        if let type = object["type"] as? String,
                           type == "content_block_delta",
                           let delta = object["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String,
                           deltaType == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                    continuation.finish()
                }
            }
        }
    }
}
