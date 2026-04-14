import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var attachedImage: NSImage?
    @Published var isLoading = false
    
    func attachScreenshot() {
        guard attachedImage == nil else {
            attachedImage = nil
            return
        }
        Task {
            if let image = await ScreenshotService.captureScreen() {
                attachedImage = image
            }
        }
    }
    
    func send() {
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
            do {
                let stream = try await GeminiAPI.shared.streamResponse(messages: messages)
                for try await chunk in stream {
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex].text += chunk
                    }
                }
            } catch {
                if let lastIndex = messages.indices.last {
                    messages[lastIndex].text = "Error: \(error.localizedDescription)"
                }
            }
            if let lastIndex = messages.indices.last {
                messages[lastIndex].isStreaming = false
            }
            isLoading = false
        }
    }
}
