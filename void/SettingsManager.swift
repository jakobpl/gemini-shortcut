//
//  SettingsManager.swift
//  gemini-shortcut
//

import Foundation
import Security
import CoreGraphics

// MARK: - Provider IDs

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case gemini, anthropic, openai, xai, moonshot, ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:    return "Google Gemini"
        case .anthropic: return "Anthropic Claude"
        case .openai:    return "OpenAI"
        case .xai:       return "xAI Grok"
        case .moonshot:  return "Moonshot Kimi"
        case .ollama:    return "Local (Ollama)"
        }
    }

    var requiresAPIKey: Bool { self != .ollama }
}

// MARK: - Panel anchor

enum PanelAnchor: String, Codable, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft:     return "Top-Left"
        case .top:         return "Top"
        case .topRight:    return "Top-Right"
        case .left:        return "Left"
        case .center:      return "Center"
        case .right:       return "Right"
        case .bottomLeft:  return "Bottom-Left"
        case .bottom:      return "Bottom"
        case .bottomRight: return "Bottom-Right"
        }
    }

    /// True when height growth should push the top edge upward (anchor pinned at bottom).
    var growsUpward: Bool {
        switch self {
        case .bottomLeft, .bottom, .bottomRight: return true
        default: return false
        }
    }

    /// True when height growth should push the bottom edge downward (anchor pinned at top).
    var growsDownward: Bool {
        switch self {
        case .topLeft, .top, .topRight: return true
        default: return false
        }
    }
}

// MARK: - SettingsManager

class SettingsManager {
    static let shared = SettingsManager()

    // Legacy single-key (kept for migration)
    private let legacyKeychainKey = "gemini-shortcut-api-key"

    private let modelKey = "selected-model"
    private let providerKey = "selected-provider"
    private let instructionsKey = "gemini-custom-instructions"
    private let toolCallingKey = "gemini-tool-calling"
    private let terminalKey = "gemini-terminal-commands"
    private let workingDirKey = "gemini-working-directory"
    private let ollamaURLKey = "ollama-base-url"
    private let panelAnchorKey = "panel-anchor"
    private let panelOffsetXKey = "panel-offset-x"
    private let panelOffsetYKey = "panel-offset-y"
    private let panelSavedOriginXKey = "panel-saved-origin-x"
    private let panelSavedOriginYKey = "panel-saved-origin-y"
    private let prewarmedKey = "prewarmed-once"

    private init() {
        migrateLegacyKeyIfNeeded()
    }

    // MARK: Legacy migration

    private func migrateLegacyKeyIfNeeded() {
        let migratedFlagKey = "migrated-legacy-gemini-key"
        if UserDefaults.standard.bool(forKey: migratedFlagKey) { return }
        if let legacy = Keychain.load(key: legacyKeychainKey),
           !legacy.isEmpty,
           legacy != "dev",
           Keychain.load(key: keychainAccount(for: .gemini)) == nil {
            Keychain.save(key: keychainAccount(for: .gemini), data: legacy)
        }
        UserDefaults.standard.set(true, forKey: migratedFlagKey)
    }

    // MARK: API keys (per-provider)

    private func keychainAccount(for provider: ProviderID) -> String {
        "api-key-\(provider.rawValue)"
    }

    func apiKey(for provider: ProviderID) -> String? {
        Keychain.load(key: keychainAccount(for: provider))
    }

    func setAPIKey(_ key: String?, for provider: ProviderID) {
        let account = keychainAccount(for: provider)
        if let key, !key.isEmpty {
            Keychain.save(key: account, data: key)
        } else {
            Keychain.delete(key: account)
        }
    }

    func hasAPIKey(for provider: ProviderID) -> Bool {
        guard let k = apiKey(for: provider) else { return false }
        return !k.isEmpty
    }

    // Convenience for the currently-selected provider
    var currentAPIKey: String? { apiKey(for: selectedProvider) }
    var hasAPIKey: Bool {
        if selectedProvider == .ollama { return true }
        return hasAPIKey(for: selectedProvider) || isDevBypassEnabled
    }
    var isDevBypassEnabled: Bool {
        currentAPIKey?.trimmingCharacters(in: .whitespaces) == "dev"
    }

    // Selected provider

    var selectedProvider: ProviderID {
        get {
            UserDefaults.standard.string(forKey: providerKey)
                .flatMap(ProviderID.init(rawValue:))
                ?? .gemini
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    // Selected model (provider-agnostic wire ID)

    var selectedModel: String {
        get {
            UserDefaults.standard.string(forKey: modelKey)
                ?? "gemini-3.1-pro-preview"
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    // Custom instructions / tool toggles / working dir (unchanged)

    var customInstructions: String {
        get { UserDefaults.standard.string(forKey: instructionsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: instructionsKey) }
    }

    var toolCallingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: toolCallingKey) }
        set { UserDefaults.standard.set(newValue, forKey: toolCallingKey) }
    }

    var runTerminalCommandsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: terminalKey) }
        set { UserDefaults.standard.set(newValue, forKey: terminalKey) }
    }

    var workingDirectory: String {
        get { UserDefaults.standard.string(forKey: workingDirKey) ?? (NSHomeDirectory() + "/Desktop") }
        set { UserDefaults.standard.set(newValue, forKey: workingDirKey) }
    }

    // Ollama

    var ollamaBaseURL: String {
        get { UserDefaults.standard.string(forKey: ollamaURLKey) ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: ollamaURLKey) }
    }

    // Panel position

    var panelAnchor: PanelAnchor {
        get {
            UserDefaults.standard.string(forKey: panelAnchorKey)
                .flatMap(PanelAnchor.init(rawValue:))
                ?? .bottom
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelAnchorKey) }
    }

    var panelOffsetX: CGFloat {
        get {
            if UserDefaults.standard.object(forKey: panelOffsetXKey) == nil { return 0 }
            return CGFloat(UserDefaults.standard.double(forKey: panelOffsetXKey))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: panelOffsetXKey) }
    }

    var panelOffsetY: CGFloat {
        get {
            if UserDefaults.standard.object(forKey: panelOffsetYKey) == nil { return 100 }
            return CGFloat(UserDefaults.standard.double(forKey: panelOffsetYKey))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: panelOffsetYKey) }
    }

    // MARK: - Panel last position (persists across hide/show)

    var panelSavedOriginX: CGFloat? {
        get {
            guard UserDefaults.standard.object(forKey: panelSavedOriginXKey) != nil else { return nil }
            return CGFloat(UserDefaults.standard.double(forKey: panelSavedOriginXKey))
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(Double(value), forKey: panelSavedOriginXKey)
            } else {
                UserDefaults.standard.removeObject(forKey: panelSavedOriginXKey)
            }
        }
    }

    var panelSavedOriginY: CGFloat? {
        get {
            guard UserDefaults.standard.object(forKey: panelSavedOriginYKey) != nil else { return nil }
            return CGFloat(UserDefaults.standard.double(forKey: panelSavedOriginYKey))
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(Double(value), forKey: panelSavedOriginYKey)
            } else {
                UserDefaults.standard.removeObject(forKey: panelSavedOriginYKey)
            }
        }
    }
}

// MARK: - Keychain

private struct Keychain {
    static func save(key: String, data: String) {
        guard let value = data.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
