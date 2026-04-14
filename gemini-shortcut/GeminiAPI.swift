//
//  GeminiAPI.swift
//  gemini-shortcut
//
//  Created by AI on 4/14/26.
//

import Foundation
import AppKit

enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case streamParseError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not configured."
        case .invalidURL: return "Invalid API endpoint."
        case .streamParseError: return "Failed to parse response stream."
        }
    }
}

@MainActor
final class GeminiAPI {
    static let shared = GeminiAPI()
    private init() {}
    
    func streamResponse(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        if SettingsManager.shared.isDevBypassEnabled {
            return devBypassStream()
        }
        
        guard let apiKey = SettingsManager.shared.apiKey, !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        
        let model = SettingsManager.shared.selectedModel
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse"
        guard let url = URL(string: endpoint) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let meaningfulMessages = messages.filter { !$0.text.isEmpty || $0.image != nil }
        let windowedMessages: [ChatMessage]
        if meaningfulMessages.count <= 6 {
            windowedMessages = meaningfulMessages
        } else {
            let summaryText = meaningfulMessages.prefix(meaningfulMessages.count - 6)
                .map { "\($0.role == .user ? "User" : "Model"): \($0.text)" }
                .joined(separator: "\n")
            let summaryMessage = ChatMessage(role: .user, text: "[Previous conversation context]\n\(summaryText)", image: nil, isStreaming: false)
            windowedMessages = [summaryMessage] + Array(meaningfulMessages.suffix(6))
        }
        
        var contents: [[String: Any]] = []
        for message in windowedMessages {
            var parts: [[String: Any]] = []
            if !message.text.isEmpty {
                parts.append(["text": message.text])
            }
            if let image = message.image, let pngData = ScreenshotService.pngData(from: image) {
                let base64 = pngData.base64EncodedString()
                parts.append([
                    "inlineData": [
                        "mimeType": "image/png",
                        "data": base64
                    ]
                ])
            }
            guard !parts.isEmpty else { continue }
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": parts
            ])
        }
        
        var body: [String: Any] = [
            "contents": contents
        ]
        
        let instructions = SettingsManager.shared.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": instructions]]
            ]
        }
        
        if SettingsManager.shared.toolCallingEnabled {
            var tools: [[String: Any]] = []
            
            if SettingsManager.shared.runTerminalCommandsEnabled {
                let terminalTool: [String: Any] = [
                    "functionDeclarations": [
                        [
                            "name": "run_terminal_command",
                            "description": "Execute a shell command on macOS and return the output. Use this when the user asks you to run code, install packages, or perform system operations.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "command": [
                                        "type": "string",
                                        "description": "The shell command to execute"
                                    ]
                                ],
                                "required": ["command"]
                            ]
                        ]
                    ]
                ]
                tools.append(terminalTool)
            }
            
            if !tools.isEmpty {
                body["tools"] = tools
                body["toolConfig"] = [
                    "functionCallingConfig": [
                        "mode": "AUTO"
                    ]
                ]
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            var text = ""
            for try await line in bytes.lines {
                text += line
            }
            throw NSError(domain: "GeminiAPI", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: text])
        }
        
        return AsyncStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard let data = json.data(using: .utf8) else { continue }
                        
                        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        
                        if let candidates = object?["candidates"] as? [[String: Any]],
                           let candidate = candidates.first {
                            
                            if let content = candidate["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]] {
                                
                                if let functionCall = parts.first?["functionCall"] as? [String: Any],
                                   let name = functionCall["name"] as? String,
                                   let args = functionCall["args"] as? [String: Any] {
                                    let result = await self.executeTool(name: name, args: args)
                                    continuation.yield(result)
                                }
                                
                                if let text = parts.first?["text"] as? String {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    private func devBypassStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let words = "This is a dev-mode test response from Gemini Shortcut. Everything is working locally."
                    .split(separator: " ")
                for word in words {
                    continuation.yield(String(word) + " ")
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                continuation.finish()
            }
        }
    }
    
    private func executeTool(name: String, args: [String: Any]) async -> String {
        switch name {
        case "run_terminal_command":
            guard let command = args["command"] as? String else {
                return "\n\n[Tool error: missing command]"
            }
            let result = await TerminalRunner.run(command: command)
            return "\n\n[Terminal output]\n```\n\(result)\n```"
        default:
            return "\n\n[Tool called: \(name)]"
        }
    }
}

// MARK: - Terminal Runner

@MainActor
enum TerminalRunner {
    static func run(command: String) async -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
