//
//  LLMProvider.swift
//  Provider-agnostic interface for streaming chat completions.
//

import Foundation

struct LLMModel: Identifiable, Hashable {
    let id: String              // wire ID, e.g. "claude-opus-4-7"
    let displayName: String     // "Claude Opus 4.7"
    let provider: ProviderID
    let supportsImages: Bool

    var compositeID: String { "\(provider.rawValue):\(id)" }
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(ProviderID)
    case invalidURL
    case http(Int, String)
    case streamParseError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            return "Missing API key for \(p.displayName). Add it in Settings."
        case .invalidURL:
            return "Invalid API endpoint."
        case .http(let code, let body):
            return "HTTP \(code): \(body)"
        case .streamParseError:
            return "Failed to parse response stream."
        }
    }
}

@MainActor
protocol LLMProvider {
    var id: ProviderID { get }
    var availableModels: [LLMModel] { get }

    /// Stream a response. The caller passes the full message history; the provider
    /// is responsible for windowing/truncation and formatting for its API.
    func streamResponse(
        messages: [ChatMessage],
        model: String,
        systemInstructions: String?
    ) async throws -> AsyncStream<String>
}
