import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            LiquidGlassContainer(cornerRadius: 28)
            LiquidGlowOverlay(cornerRadius: 28)
            
            if !SettingsManager.shared.hasAPIKey {
                noAPIKeyView
            } else {
                chatBody
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    
    private var noAPIKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.accentColor)
            
            Text("Configure your API key in the menu bar to get started.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(width: 520, height: 120)
        .padding(.horizontal, 24)
    }
    
    private var chatBody: some View {
        VStack(spacing: 0) {
            messageList
            if viewModel.attachedImage != nil {
                attachedImagePreview
            }
            inputBarContainer
        }
        .frame(minWidth: 620, maxWidth: 620, minHeight: 60, maxHeight: .infinity)
        .onAppear { isInputFocused = true }
        .onChange(of: viewModel.messages.count) { _, _ in updateHeight() }
        .onChange(of: viewModel.isLoading) { _, _ in updateHeight() }
        .onChange(of: viewModel.attachedImage) { _, _ in updateHeight() }
    }
    
    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.messages) { message in
                    messageBubble(for: message)
                }
                
                if showThinkingIndicator {
                    HStack {
                        Spacer()
                        LiquidOrb()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }
    
    private var showThinkingIndicator: Bool {
        viewModel.isLoading && (viewModel.messages.last?.text.isEmpty ?? true)
    }
    
    private func messageBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 6) {
                if let image = message.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LiquidGlassContainer(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            
            if message.role == .model {
                Spacer()
            }
        }
    }
    
    private var attachedImagePreview: some View {
        HStack {
            Spacer()
            if let image = viewModel.attachedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    private var inputBarContainer: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if viewModel.inputText.isEmpty {
                    Text("Ask Gemini...")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                
                TextField("", text: $viewModel.inputText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.send()
                        isInputFocused = true
                    }
            }
            
            Button(action: { viewModel.attachScreenshot() }) {
                Image(systemName: viewModel.attachedImage == nil ? "camera" : "camera.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(viewModel.attachedImage == nil ? Color.white.opacity(0.6) : Color.accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 32, height: 32)
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var sendButton: some View {
        Button(action: { viewModel.send() }) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(emptyInput ? Color.white.opacity(0.1) : Color.accentColor)
                )
                .foregroundStyle(emptyInput ? Color.white.opacity(0.4) : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(emptyInput)
    }
    
    private var emptyInput: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func updateHeight() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let hasContent = !viewModel.messages.isEmpty || viewModel.isLoading || viewModel.attachedImage != nil
            let height: CGFloat = hasContent ? 480 : 70
            NotificationCenter.default.post(name: .geminiResizePanel, object: height)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let geminiResizePanel = Notification.Name("GeminiResizePanel")
}
