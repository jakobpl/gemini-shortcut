import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var attachedImage: NSImage?
    @Published var isLoading = false
    @Published var isRecording = false
    @Published var editMessageIndex: Int?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let messagesKey = "gemini-chat-messages"
    private let messagesTimestampKey = "gemini-chat-timestamp"
    private let messageLifespan: TimeInterval = 300  // 5 minutes

    // Sentinel prefix used to pass generated image data through the text stream
    static let imageSentinel = "\u{01}IMAGE:"

    init() {
        loadMessages()
    }

    // MARK: - Persistence

    private func loadMessages() {
        guard
            let data = UserDefaults.standard.data(forKey: messagesKey),
            let savedAt = UserDefaults.standard.object(forKey: messagesTimestampKey) as? Date,
            Date().timeIntervalSince(savedAt) < messageLifespan
        else { return }

        guard let persisted = try? JSONDecoder().decode([PersistedMessage].self, from: data) else { return }

        messages = persisted.map { p in
            ChatMessage(
                id: UUID(uuidString: p.id) ?? UUID(),
                role: p.role == "user" ? .user : .model,
                text: p.text,
                image: nil,
                isStreaming: false,
                generatedImages: p.generatedImages,
                rating: p.rating.flatMap { MessageRating(rawValue: $0) },
                timestamp: Date(timeIntervalSince1970: p.timestamp)
            )
        }
    }

    func saveMessages() {
        let persisted = messages.filter { !$0.isStreaming }.map { m in
            PersistedMessage(
                id: m.id.uuidString,
                role: m.role == .user ? "user" : "model",
                text: m.text,
                generatedImages: m.generatedImages,
                timestamp: m.timestamp.timeIntervalSince1970,
                rating: m.rating?.rawValue
            )
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: messagesKey)
        UserDefaults.standard.set(Date(), forKey: messagesTimestampKey)
    }

    func clearMessages() {
        messages = []
        UserDefaults.standard.removeObject(forKey: messagesKey)
        UserDefaults.standard.removeObject(forKey: messagesTimestampKey)
    }

    // MARK: - Mic / Speech-to-Text

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard status == .authorized, let self else { return }
                    self.startRecording()
                }
            }
        }
    }

    private func startRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.inputText = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isRecording = false
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            cleanupAudio()
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        cleanupAudio()
    }

    private func cleanupAudio() {
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Attachment

    func attachScreenshot() {
        guard attachedImage == nil else {
            attachedImage = nil
            return
        }
        let screen = NSApp.keyWindow?.screen
        Task {
            if let image = await ScreenshotService.captureScreen(for: screen) {
                attachedImage = image
            }
        }
    }

    func attachFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = "Attach Image"
        panel.prompt = "Attach"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        attachedImage = image
    }

    // MARK: - Send

    func send() {
        if isRecording { stopRecording() }

        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: prompt, image: attachedImage, isStreaming: false)
        messages.append(userMessage)

        let placeholder = ChatMessage(role: .model, text: "", image: nil, isStreaming: true)
        messages.append(placeholder)

        isLoading = true
        inputText = ""
        attachedImage = nil

        Task {
            defer {
                isLoading = false
                saveMessages()
            }
            do {
                let stream = try await GeminiAPI.shared.streamResponse(messages: messages)
                for try await chunk in stream {
                    if chunk.hasPrefix(ChatViewModel.imageSentinel) {
                        let base64 = String(chunk.dropFirst(ChatViewModel.imageSentinel.count))
                        if let imageData = Data(base64Encoded: base64),
                           let lastIndex = messages.indices.last {
                            messages[lastIndex].generatedImages.append(imageData)
                        }
                    } else if let lastIndex = messages.indices.last {
                        messages[lastIndex].text += chunk
                        messages[lastIndex].revealedCharCount = min(messages[lastIndex].revealedCharCount + chunk.count, messages[lastIndex].text.count)
                    }
                }
            } catch {
                if let lastIndex = messages.indices.last {
                    messages[lastIndex].text = "Error: \(error.localizedDescription)"
                }
            }
            if let lastIndex = messages.indices.last {
                messages[lastIndex].isStreaming = false
                messages[lastIndex].revealedCharCount = messages[lastIndex].text.count
            }
        }
    }
}
