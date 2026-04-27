//
//  ProviderRegistry.swift
//  Maps ProviderID → concrete LLMProvider instance and exposes the active one.
//

import Foundation

@MainActor
enum ProviderRegistry {
    static func provider(for id: ProviderID) -> LLMProvider {
        switch id {
        case .gemini:    return GeminiProvider.shared
        case .anthropic: return AnthropicProvider.shared
        case .openai:    return OpenAIProvider.shared
        case .xai:       return XAIProvider.shared
        case .moonshot:  return MoonshotProvider.shared
        case .ollama:    return OllamaProvider.shared
        }
    }

    static var current: LLMProvider {
        provider(for: SettingsManager.shared.selectedProvider)
    }

    static var allModels: [LLMModel] {
        ProviderID.allCases.flatMap { provider(for: $0).availableModels }
    }

    static func models(for id: ProviderID) -> [LLMModel] {
        provider(for: id).availableModels
    }

    /// Returns the model whose wire ID matches `id` if any provider declares it,
    /// else nil. Useful when the user's saved model belongs to a provider they
    /// haven't selected.
    static func model(byWireID id: String) -> LLMModel? {
        allModels.first { $0.id == id }
    }
}
