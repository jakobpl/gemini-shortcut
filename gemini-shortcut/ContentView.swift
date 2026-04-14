import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var isHovering = false
    @State private var contentAppeared = false
    @State private var inputAppeared = false

    var body: some View {
        ZStack {
            // Real macOS 26 Liquid Glass — refractive, chromatic, adapts to background
            LiquidGlassContainer(cornerRadius: 28)

            if !SettingsManager.shared.hasAPIKey {
                noAPIKeyView
            } else {
                chatBody
            }

            // Close button — fades in on hover, top-right corner
            closeButton
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: .geminiClosePanel, object: nil)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Circle().glassEffect(in: Circle()))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            Spacer()
        }
        .opacity(isHovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    // MARK: - No API Key

    private var noAPIKeyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Configure your API key in the menu bar to get started.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(width: 520, height: 100)
        .padding(.horizontal, 24)
    }

    // MARK: - Chat Body

    private var chatBody: some View {
        VStack(spacing: 0) {
            messageList
                .offset(y: contentAppeared ? 0 : 22)
                .opacity(contentAppeared ? 1 : 0)

            if viewModel.attachedImage != nil {
                attachedImagePreview
                    .offset(y: contentAppeared ? 0 : 10)
                    .opacity(contentAppeared ? 1 : 0)
            }

            inputBarContainer
                .offset(y: inputAppeared ? 0 : 14)
                .opacity(inputAppeared ? 1 : 0)
        }
        .frame(minWidth: 580, maxWidth: 580, minHeight: 60, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
            // Staggered spring entrance — content flows in, then input settles
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                contentAppeared = true
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75).delay(0.08)) {
                inputAppeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .geminiPanelDidShow)) { _ in
            // Re-establish focus every time the panel animates in (onAppear only fires once)
            isInputFocused = true
        }
        .onChange(of: viewModel.messages.count) { _, _ in updateHeight() }
        .onChange(of: viewModel.isLoading) { _, _ in updateHeight() }
        .onChange(of: viewModel.attachedImage) { _, _ in updateHeight() }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale(
                                    scale: 0.88,
                                    anchor: message.role == .user ? .bottomTrailing : .bottomLeading
                                ).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if showThinkingIndicator {
                        HStack {
                            LiquidOrb()
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: viewModel.messages.count)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: showThinkingIndicator)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var showThinkingIndicator: Bool {
        viewModel.isLoading && (viewModel.messages.last?.text.isEmpty ?? true)
    }

    // MARK: - Message Bubble

    private func messageBubble(for message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 6) {
                if let image = message.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .textSelection(.enabled)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.75)
                            )
                    }
                }
            )

            if message.role == .model { Spacer(minLength: 60) }
        }
    }

    // MARK: - Attached Image Preview

    private var attachedImagePreview: some View {
        HStack {
            Spacer()
            if let image = viewModel.attachedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.75)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBarContainer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if viewModel.inputText.isEmpty {
                    Text("Ask Gemini…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .allowsHitTesting(false)
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

            // Screenshot attach
            Button(action: { viewModel.attachScreenshot() }) {
                Image(systemName: viewModel.attachedImage == nil ? "camera" : "camera.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(viewModel.attachedImage == nil
                                     ? Color.white.opacity(0.5)
                                     : Color.accentColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            // Send / Loading
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 28, height: 28)
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    private var sendButton: some View {
        Button(action: {
            viewModel.send()
        }) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(emptyInput ? Color.white.opacity(0.35) : Color.white)
                .frame(width: 26, height: 26)
                .background(
                    Group {
                        if emptyInput {
                            Circle().glassEffect(in: Circle())
                        } else {
                            Circle().fill(Color.accentColor)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(emptyInput)
        .animation(.easeInOut(duration: 0.15), value: emptyInput)
    }

    private var emptyInput: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func updateHeight() {
        let hasContent = !viewModel.messages.isEmpty || viewModel.isLoading || viewModel.attachedImage != nil
        let height: CGFloat = hasContent ? 480 : 70
        NotificationCenter.default.post(name: .geminiResizePanel, object: height)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let geminiResizePanel  = Notification.Name("GeminiResizePanel")
    static let geminiClosePanel   = Notification.Name("GeminiClosePanel")
    static let geminiPanelDidShow = Notification.Name("GeminiPanelDidShow")
}
