import SwiftUI
import Speech
import AVFoundation

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var attachedImages: [NSImage] = []
    var isLoading = false
    var isRecording = false
    var editMessageIndex: Int?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var streamingTask: Task<Void, Never>?

    // Buffered display: chunks land in pendingBuffer, a Timer drains them at a
    // steady cadence into the visible message text — smooths over uneven network
    // packet arrival so the stream feels even.
    private var pendingBuffer = ""
    private var streamingMessageIndex: Int?
    private var displayTimer: Timer?
    private var streamFinished = false
    private let charsPerTick = 4

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
                images: [],
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

        guard let speechRecognizer else {
            NSLog("[dictation] SFSpeechRecognizer unavailable for locale \(Locale.current.identifier)")
            return
        }
        guard speechRecognizer.isAvailable else {
            NSLog("[dictation] SFSpeechRecognizer not available right now")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.inputText = result.bestTranscription.formattedString
            }
            if let error {
                NSLog("[dictation] recognitionTask error: \(error.localizedDescription)")
            }
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                if self.tapInstalled {
                    inputNode.removeTap(onBus: 0)
                    self.tapInstalled = false
                }
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isRecording = false
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            NSLog("[dictation] audioEngine.start() failed: \(error.localizedDescription)")
            cleanupAudio()
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        cleanupAudio()
    }

    private func cleanupAudio() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Attachment

    func attachScreenshot() {
        let screen = NSApp.keyWindow?.screen
        Task {
            if let image = await ScreenshotService.captureScreen(for: screen) {
                attachedImages.append(image)
            }
        }
    }

    func attachRegionScreenshot() {
        Task {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snippet.png")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-s", tmp.path]
            try? proc.run()
            proc.waitUntilExit()
            if let img = NSImage(contentsOf: tmp) {
                await MainActor.run { self.attachedImages.append(img) }
                try? FileManager.default.removeItem(at: tmp)
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
        attachedImages.append(image)
    }

    // MARK: - Send

    func send() {
        if isRecording { stopRecording() }

        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: prompt, images: attachedImages, isStreaming: false)
        messages.append(userMessage)

        let placeholder = ChatMessage(role: .model, text: "", images: [], isStreaming: true)
        messages.append(placeholder)

        isLoading = true
        inputText = ""
        attachedImages = []

        streamingMessageIndex = messages.count - 1
        streamFinished = false
        pendingBuffer = ""
        startDisplayTimer()

        let provider = ProviderRegistry.current
        let modelID = SettingsManager.shared.selectedModel
        let systemInstructions = SettingsManager.shared.customInstructions
        let snapshot = messages

        streamingTask = Task { @MainActor in
            defer {
                isLoading = false
                streamFinished = true
                saveMessages()
            }
            do {
                let stream = try await provider.streamResponse(
                    messages: snapshot,
                    model: modelID,
                    systemInstructions: systemInstructions
                )
                for try await chunk in stream {
                    if chunk.hasPrefix(ChatViewModel.imageSentinel) {
                        let base64 = String(chunk.dropFirst(ChatViewModel.imageSentinel.count))
                        if let imageData = Data(base64Encoded: base64),
                           let idx = streamingMessageIndex,
                           messages.indices.contains(idx) {
                            messages[idx].generatedImages.append(imageData)
                        }
                    } else {
                        pendingBuffer += chunk
                    }
                }
            } catch {
                pendingBuffer += "\n\nError: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Buffered Display Loop

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.tickDisplay()
            }
        }
    }

    private func tickDisplay() {
        guard let idx = streamingMessageIndex,
              messages.indices.contains(idx) else {
            stopDisplayTimer()
            return
        }

        if !pendingBuffer.isEmpty {
            let take = min(pendingBuffer.count, charsPerTick)
            let prefix = String(pendingBuffer.prefix(take))
            pendingBuffer.removeFirst(take)
            messages[idx].text += prefix
            messages[idx].revealedCharCount = messages[idx].text.count
            messages[idx].revealedWordCount = wordCount(in: messages[idx].text)
            return
        }

        if streamFinished {
            messages[idx].isStreaming = false
            messages[idx].revealedCharCount = messages[idx].text.count
            messages[idx].revealedWordCount = wordCount(in: messages[idx].text)
            stopDisplayTimer()
        }
    }

    private func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        streamingMessageIndex = nil
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isLoading = false
        streamFinished = true
        pendingBuffer = ""
        stopDisplayTimer()

        if let lastIndex = messages.indices.last, messages[lastIndex].role == .model {
            messages.removeLast()
        }

        if let userMsgIndex = messages.lastIndex(where: { $0.role == .user }) {
            inputText = messages[userMsgIndex].text
        }

        saveMessages()
    }
}
