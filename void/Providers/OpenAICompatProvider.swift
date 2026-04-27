//
//  OpenAICompatProvider.swift
//  Shared streaming client for OpenAI-compatible APIs (OpenAI, xAI, Moonshot).
//

import Foundation
import AppKit

/// Concrete subclasses just supply the endpoint, models, and provider id;
/// the wire format is identical (OpenAI's chat/completions with stream:true).
@MainActor
class OpenAICompatProvider: LLMProvider {
    let id: ProviderID
    let baseURL: String
    let availableModels: [LLMModel]

    init(id: ProviderID, baseURL: String, availableModels: [LLMModel]) {
        self.id = id
        self.baseURL = baseURL
        self.availableModels = availableModels
    }

    func streamResponse(
        messages: [ChatMessage],
        model: String,
        systemInstructions: String?
    ) async throws -> AsyncStream<String> {
        if SettingsManager.shared.isDevBypassEnabled {
            return GeminiProvider.devBypassStream()
        }

        guard let apiKey = SettingsManager.shared.apiKey(for: id), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(id)
        }

        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else { throw LLMError.invalidURL }

        // Window: drop empty messages, keep last 6 + a summary if longer.
        let meaningful = messages.filter { !$0.text.isEmpty || !$0.images.isEmpty }
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

        // Build OpenAI message array.
        var apiMessages: [[String: Any]] = []
        let sys = (systemInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }

        for message in windowed {
            let role = message.role == .user ? "user" : "assistant"
            if message.images.isEmpty {
                apiMessages.append(["role": role, "content": message.text])
            } else {
                var parts: [[String: Any]] = []
                if !message.text.isEmpty {
                    parts.append(["type": "text", "text": message.text])
                }
                for image in message.images {
                    if let pngData = ScreenshotService.pngData(from: image) {
                        let dataURL = "data:image/png;base64,\(pngData.base64EncodedString())"
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": dataURL]
                        ])
                    }
                }
                apiMessages.append(["role": role, "content": parts])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
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

// MARK: - Concrete providers

@MainActor
final class OpenAIProvider: OpenAICompatProvider {
    static let shared = OpenAIProvider()
    private init() {
        super.init(
            id: .openai,
            baseURL: "https://api.openai.com/v1",
            availableModels: [
                LLMModel(id: "gpt-5.5",      displayName: "GPT-5.5",      provider: .openai, supportsImages: true),
                LLMModel(id: "gpt-5",        displayName: "GPT-5",        provider: .openai, supportsImages: true),
                LLMModel(id: "gpt-5-mini",   displayName: "GPT-5 Mini",   provider: .openai, supportsImages: true),
            ]
        )
    }
}

@MainActor
final class XAIProvider: OpenAICompatProvider {
    static let shared = XAIProvider()
    private init() {
        super.init(
            id: .xai,
            baseURL: "https://api.x.ai/v1",
            availableModels: [
                LLMModel(id: "grok-4.20",       displayName: "Grok 4.20",       provider: .xai, supportsImages: true),
                LLMModel(id: "grok-4",          displayName: "Grok 4",          provider: .xai, supportsImages: true),
                LLMModel(id: "grok-4-mini",     displayName: "Grok 4 Mini",     provider: .xai, supportsImages: false),
            ]
        )
    }
}

@MainActor
final class MoonshotProvider: OpenAICompatProvider {
    static let shared = MoonshotProvider()
    private init() {
        super.init(
            id: .moonshot,
            baseURL: "https://api.moonshot.ai/v1",
            availableModels: [
                LLMModel(id: "kimi-2.6",          displayName: "Kimi 2.6",          provider: .moonshot, supportsImages: true),
                LLMModel(id: "kimi-2",            displayName: "Kimi 2",            provider: .moonshot, supportsImages: true),
                LLMModel(id: "moonshot-v1-32k",   displayName: "Moonshot v1 32k",   provider: .moonshot, supportsImages: false),
            ]
        )
    }
}
