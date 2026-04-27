//
//  GeminiProvider.swift
//  Google Gemini provider — supports streaming, image inputs, and tool calling
//  (image generation + terminal execution).
//

import Foundation
import AppKit

@MainActor
final class GeminiProvider: LLMProvider {
    static let shared = GeminiProvider()
    private init() {}

    let id: ProviderID = .gemini

    let availableModels: [LLMModel] = [
        LLMModel(id: "gemini-3.1-pro-preview",        displayName: "Gemini 3.1 Pro",        provider: .gemini, supportsImages: true),
        LLMModel(id: "gemini-3.1-flash-lite-preview", displayName: "Gemini 3.1 Flash Lite", provider: .gemini, supportsImages: true),
    ]

    func streamResponse(
        messages: [ChatMessage],
        model: String,
        systemInstructions: String?
    ) async throws -> AsyncStream<String> {
        if SettingsManager.shared.isDevBypassEnabled {
            return Self.devBypassStream()
        }

        guard let apiKey = SettingsManager.shared.apiKey(for: .gemini), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey(.gemini)
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse"
        guard let url = URL(string: endpoint) else { throw LLMError.invalidURL }

        // Message windowing: summarise older messages, keep 6 most recent
        let meaningful = messages.filter { !$0.text.isEmpty || !$0.images.isEmpty }
        let windowed: [ChatMessage]
        if meaningful.count <= 6 {
            windowed = meaningful
        } else {
            let summaryText = meaningful.prefix(meaningful.count - 6)
                .map { "\($0.role == .user ? "User" : "Model"): \($0.text)" }
                .joined(separator: "\n")
            let summary = ChatMessage(
                role: .user,
                text: "[Previous conversation context]\n\(summaryText)",
                images: [],
                isStreaming: false
            )
            windowed = [summary] + Array(meaningful.suffix(6))
        }

        var contents: [[String: Any]] = []
        for message in windowed {
            var parts: [[String: Any]] = []
            if !message.text.isEmpty { parts.append(["text": message.text]) }
            for image in message.images {
                if let pngData = ScreenshotService.pngData(from: image) {
                    parts.append([
                        "inlineData": [
                            "mimeType": "image/png",
                            "data": pngData.base64EncodedString()
                        ]
                    ])
                }
            }
            guard !parts.isEmpty else { continue }
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": parts
            ])
        }

        var body: [String: Any] = ["contents": contents]
        let instructions = (systemInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            body["systemInstruction"] = ["parts": [["text": instructions]]]
        }

        // Tools: image-gen always offered; terminal execution gated by user settings.
        var tools: [[String: Any]] = []
        tools.append([
            "functionDeclarations": [[
                "name": "generate_image",
                "description": "Generate an image from a text description using AI image generation. Call this whenever the user asks to create, draw, or generate an image.",
                "parameters": [
                    "type": "object",
                    "properties": ["prompt": ["type": "string", "description": "A detailed description of the image to generate"]],
                    "required": ["prompt"]
                ]
            ]]
        ])

        if SettingsManager.shared.toolCallingEnabled && SettingsManager.shared.runTerminalCommandsEnabled {
            let workingDir = SettingsManager.shared.workingDirectory
            tools.append([
                "functionDeclarations": [[
                    "name": "run_terminal_command",
                    "description": "Execute a shell/bash command on the user's macOS computer and return its output. Working directory is '\(workingDir)'. Chain steps with && for multi-step tasks. Prefer absolute paths.",
                    "parameters": [
                        "type": "object",
                        "properties": ["command": ["type": "string", "description": "The bash command to execute"]],
                        "required": ["command"]
                    ]
                ]]
            ])
        }

        body["tools"] = tools
        body["toolConfig"] = ["functionCallingConfig": ["mode": "AUTO"]]

        let baseBody = body
        let baseContents = contents
        let apiKeyForImage = apiKey

        return AsyncStream { continuation in
            Task { @MainActor in
                do {
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
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            var err = ""
                            for try await line in bytes.lines { err += line }
                            throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? 0, err)
                        }

                        var pendingToolCalls: [(name: String, args: [String: Any])] = []
                        var modelParts: [[String: Any]] = []
                        var accumulated = ""

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
                                        accumulated += text
                                    }
                                }
                            }
                        }

                        if pendingToolCalls.isEmpty { break }

                        var modelTurnParts = modelParts
                        if !accumulated.isEmpty { modelTurnParts.insert(["text": accumulated], at: 0) }
                        conversationContents.append(["role": "model", "parts": modelTurnParts])

                        var functionResponseParts: [[String: Any]] = []
                        for (name, args) in pendingToolCalls {
                            let result = await Self.executeTool(name: name, args: args, apiKey: apiKeyForImage)
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
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Tool Execution

    private static func executeTool(name: String, args: [String: Any], apiKey: String) async -> String {
        switch name {
        case "generate_image":
            guard let prompt = args["prompt"] as? String else {
                return "\n\n[Image generation error: missing prompt]"
            }
            if let imageData = await generateImage(prompt: prompt, apiKey: apiKey) {
                return "\(ChatViewModel.imageSentinel)\(imageData.base64EncodedString())"
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

    private static func generateImage(prompt: String, apiKey: String) async -> Data? {
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

    static func devBypassStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let words = "This is a dev-mode test response from \(SettingsManager.shared.selectedProvider.displayName). Streaming locally without hitting the network."
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

// MARK: - Terminal Runner (used by Gemini's run_terminal_command tool)

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
