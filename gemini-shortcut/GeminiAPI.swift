//
//  GeminiAPI.swift
//  gemini-shortcut
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

// MARK: - GeminiAPI

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

        // Message windowing: summarise older messages, keep 6 most recent
        let meaningfulMessages = messages.filter { !$0.text.isEmpty || $0.image != nil }
        let windowedMessages: [ChatMessage]
        if meaningfulMessages.count <= 6 {
            windowedMessages = meaningfulMessages
        } else {
            let summaryText = meaningfulMessages.prefix(meaningfulMessages.count - 6)
                .map { "\($0.role == .user ? "User" : "Model"): \($0.text)" }
                .joined(separator: "\n")
            let summaryMessage = ChatMessage(
                role: .user,
                text: "[Previous conversation context]\n\(summaryText)",
                image: nil,
                isStreaming: false
            )
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

        var body: [String: Any] = ["contents": contents]

        let instructions = SettingsManager.shared.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            body["systemInstruction"] = ["parts": [["text": instructions]]]
        }

        // Build tools list — image generation is always offered;
        // terminal execution is gated by user settings.
        var tools: [[String: Any]] = []

        let imageGenDecl: [String: Any] = [
            "functionDeclarations": [
                [
                    "name": "generate_image",
                    "description": "Generate an image from a text description using AI image generation. Call this whenever the user asks to create, draw, or generate an image.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "prompt": [
                                "type": "string",
                                "description": "A detailed description of the image to generate"
                            ]
                        ],
                        "required": ["prompt"]
                    ]
                ]
            ]
        ]
        tools.append(imageGenDecl)

        if SettingsManager.shared.toolCallingEnabled && SettingsManager.shared.runTerminalCommandsEnabled {
            let workingDir = SettingsManager.shared.workingDirectory
            let terminalDecl: [String: Any] = [
                "functionDeclarations": [
                    [
                        "name": "run_terminal_command",
                        "description": "Execute a shell/bash command on the user's macOS computer and return its output. The working directory is '\(workingDir)' — use this path when creating files unless the user specifies otherwise. Chain multiple steps with && for multi-step tasks (e.g. create a file, then run it). Prefer absolute paths.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "command": [
                                    "type": "string",
                                    "description": "The bash command to execute"
                                ]
                            ],
                            "required": ["command"]
                        ]
                    ]
                ]
            ]
            tools.append(terminalDecl)
        }

        body["tools"] = tools
        body["toolConfig"] = ["functionCallingConfig": ["mode": "AUTO"]]

        // Capture variables needed inside the async stream closure
        let baseBody = body
        let baseContents = contents

        return AsyncStream { continuation in
            Task {
                do {
                    // Multi-turn tool-calling loop: keep going until the model
                    // returns pure text with no function calls.
                    var conversationContents = baseContents
                    let maxRounds = 8

                    for _ in 0..<maxRounds {
                        var loopBody = baseBody
                        loopBody["contents"] = conversationContents

                        var loopRequest = URLRequest(url: url)
                        loopRequest.httpMethod = "POST"
                        loopRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        loopRequest.httpBody = try JSONSerialization.data(withJSONObject: loopBody)

                        let (bytes, response) = try await URLSession.shared.bytes(for: loopRequest)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            var errText = ""
                            for try await line in bytes.lines { errText += line }
                            throw NSError(
                                domain: "GeminiAPI",
                                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                userInfo: [NSLocalizedDescriptionKey: errText]
                            )
                        }

                        // Collect this turn's tool calls and text
                        var pendingToolCalls: [(name: String, args: [String: Any])] = []
                        var modelParts: [[String: Any]] = []
                        var accumulatedText = ""

                        for try await line in bytes.lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let json = String(line.dropFirst(6))
                            guard let data = json.data(using: .utf8) else { continue }
                            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

                            if let candidates = object?["candidates"] as? [[String: Any]],
                               let content = candidates.first?["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]] {
                                for part in parts {
                                    if let fc = part["functionCall"] as? [String: Any],
                                       let name = fc["name"] as? String,
                                       let args = fc["args"] as? [String: Any] {
                                        pendingToolCalls.append((name: name, args: args))
                                        modelParts.append(["functionCall": ["name": name, "args": args]])
                                    } else if let text = part["text"] as? String {
                                        continuation.yield(text)
                                        accumulatedText += text
                                    }
                                }
                            }
                        }

                        // No tool calls → model is done
                        if pendingToolCalls.isEmpty { break }

                        // Build model turn content for the next round
                        var modelTurnParts = modelParts
                        if !accumulatedText.isEmpty {
                            modelTurnParts.insert(["text": accumulatedText], at: 0)
                        }
                        conversationContents.append(["role": "model", "parts": modelTurnParts])

                        // Execute each tool and collect responses
                        var functionResponseParts: [[String: Any]] = []
                        for (name, args) in pendingToolCalls {
                            let result = await self.executeTool(name: name, args: args)
                            if result.hasPrefix(ChatViewModel.imageSentinel) {
                                continuation.yield(result)
                                functionResponseParts.append([
                                    "functionResponse": ["name": name, "response": ["output": "Image generated."]]
                                ])
                            } else {
                                continuation.yield(result)
                                functionResponseParts.append([
                                    "functionResponse": ["name": name, "response": ["output": result]]
                                ])
                            }
                        }
                        conversationContents.append(["role": "user", "parts": functionResponseParts])
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, args: [String: Any]) async -> String {
        switch name {
        case "generate_image":
            guard let prompt = args["prompt"] as? String else {
                return "\n\n[Image generation error: missing prompt]"
            }
            if let imageData = await generateImage(prompt: prompt) {
                let base64 = imageData.base64EncodedString()
                return "\(ChatViewModel.imageSentinel)\(base64)"
            } else {
                return "\n\n[Image generation failed — ensure your API key has Imagen access]"
            }

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

    // MARK: - Imagen API

    private func generateImage(prompt: String) async -> Data? {
        guard let apiKey = SettingsManager.shared.apiKey, !apiKey.isEmpty else { return nil }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "instances": [["prompt": prompt]],
            "parameters": ["sampleCount": 1]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let predictions = json["predictions"] as? [[String: Any]],
            let first = predictions.first,
            let base64 = first["bytesBase64Encoded"] as? String,
            let imageData = Data(base64Encoded: base64)
        else { return nil }

        return imageData
    }

    // MARK: - Dev Bypass

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
}

// MARK: - Terminal Runner

@MainActor
enum TerminalRunner {
    static func run(command: String) async -> String {
        let workingDir = SettingsManager.shared.workingDirectory
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = URL(fileURLWithPath: workingDir)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? "(no output)" : output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
