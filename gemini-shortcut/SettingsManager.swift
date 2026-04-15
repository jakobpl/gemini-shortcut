//
//  SettingsManager.swift
//  gemini-shortcut
//
//  Created by AI on 4/14/26.
//

import Foundation
import Security

class SettingsManager {
    static let shared = SettingsManager()
    
    private let keychainKey = "gemini-shortcut-api-key"
    private let modelKey = "gemini-selected-model"
    private let instructionsKey = "gemini-custom-instructions"
    private let toolCallingKey = "gemini-tool-calling"
    private let terminalKey = "gemini-terminal-commands"
    private let workingDirKey = "gemini-working-directory"
    
    private init() {}
    
    var hasAPIKey: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }
    
    var isDevBypassEnabled: Bool {
        apiKey?.trimmingCharacters(in: .whitespaces) == "dev"
    }
    
    var apiKey: String? {
        get { Keychain.load(key: keychainKey) ?? "dev" }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.save(key: keychainKey, data: newValue)
            } else {
                Keychain.delete(key: keychainKey)
            }
        }
    }
    
    var selectedModel: String {
        get {
            UserDefaults.standard.string(forKey: modelKey)
                ?? "gemini-3.1-pro-preview"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
        }
    }
    
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
}

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
