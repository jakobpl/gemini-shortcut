import SwiftUI

// MARK: - Scroll Position Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var isHovering = false
    @State private var contentAppeared = false
    @State private var inputAppeared = false
    @State private var showingAttachmentPreview = false
    @State private var inputBarVisible = true
    @State private var lastScrollOffset: CGFloat = 0

    @AppStorage("gemini-selected-model") private var selectedModel: String = "gemini-3.1-pro-preview"

    private var hasContent: Bool {
        !viewModel.messages.isEmpty || viewModel.isLoading
    }

    var body: some View {
        ZStack {
            if !SettingsManager.shared.hasAPIKey {
                noAPIKeyView
            } else {
                chatBody
            }
            actionButtons
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(hasContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: hasContent)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
        }
    }

    // MARK: - Action Buttons (top corners, visible on hover)

    private var actionButtons: some View {
        VStack {
            HStack {
                Spacer()
                // Clear chat — top-right, only when messages exist
                if !viewModel.messages.isEmpty {
                    Button(action: {
                        viewModel.clearMessages()
                        updateHeight()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
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
                .offset(y: (inputAppeared && inputBarVisible) ? 0 : 100)
                .opacity((inputAppeared && inputBarVisible) ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: inputBarVisible)
        }
        .frame(minWidth: 580, maxWidth: 580, minHeight: 60, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                contentAppeared = true
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75).delay(0.08)) {
                inputAppeared = true
            }
            // Immediately resize if messages are already loaded from persistence
            updateHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .geminiPanelDidShow)) { _ in
            isInputFocused = true
            updateHeight()
        }
        .onChange(of: viewModel.messages.count) { _, _ in updateHeight() }
        .onChange(of: viewModel.isLoading) { _, _ in updateHeight() }
        .onChange(of: viewModel.attachedImage) { _, _ in updateHeight() }
        .onChange(of: viewModel.messages) { _, _ in viewModel.saveMessages() }
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
                        HStack(spacing: 8) {
                            TypingDotsView()
                                .frame(height: 6)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: viewModel.messages.count)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: showThinkingIndicator)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scrollview")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scrollview")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                if viewModel.messages.isEmpty {
                    inputBarVisible = true
                } else {
                    if offset < lastScrollOffset {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            inputBarVisible = false
                        }
                    } else if offset > lastScrollOffset {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            inputBarVisible = true
                        }
                    }
                }
                lastScrollOffset = offset
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    inputBarVisible = true
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var showThinkingIndicator: Bool {
        viewModel.isLoading && (viewModel.messages.last?.text.isEmpty ?? true)
    }

    // MARK: - Message Bubble

    @State private var hoveredMessageId: UUID?

    private func messageBubble(for message: ChatMessage) -> some View {
        VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                if message.role == .user { Spacer(minLength: 60) }

                let bubbleContent = VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 8) {
                    // User-attached image
                    if let image = message.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Text / code blocks
                    if !message.text.isEmpty {
                        if message.role == .model {
                            if message.isStreaming {
                                let revealedText = String(message.text.prefix(message.revealedCharCount))
                                MessageContentView(text: revealedText)
                                    .opacity(message.revealedCharCount > 0 ? 1 : 0.3)
                                    .animation(.easeOut(duration: 0.1), value: message.revealedCharCount)
                            } else {
                                MessageContentView(text: message.text)
                            }
                        } else {
                            Text(message.text)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .textSelection(.enabled)
                                .lineSpacing(3)
                        }
                    }

                    // AI-generated images
                    ForEach(message.generatedImages.indices, id: \.self) { idx in
                        GeneratedImageView(imageData: message.generatedImages[idx])
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if message.role == .user {
                    bubbleContent
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.12)).interactive(), in: .rect(cornerRadius: 18, style: .continuous))
                } else {
                    bubbleContent
                        .glassEffect(.regular.tint(Color.clear).interactive(), in: .rect(cornerRadius: 18, style: .continuous))
                }

                if message.role == .model { Spacer(minLength: 60) }
            }
            .onHover { isHovered in
                withAnimation(.easeInOut(duration: 0.2)) {
                    hoveredMessageId = isHovered ? message.id : nil
                }
            }

            // Action buttons (only on hover)
            if hoveredMessageId == message.id {
                HStack(spacing: 8) {
                    if message.role == .model {
                        // Positive rating
                        Button(action: {
                            var msg = message
                            msg.rating = msg.rating == .positive ? nil : .positive
                            if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                                viewModel.messages[idx] = msg
                            }
                        }) {
                            Image(systemName: message.rating == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.rating == .positive ? Color.accentColor : Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        // Negative rating
                        Button(action: {
                            var msg = message
                            msg.rating = msg.rating == .negative ? nil : .negative
                            if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                                viewModel.messages[idx] = msg
                            }
                        }) {
                            Image(systemName: message.rating == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.rating == .negative ? Color.accentColor : Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        // Copy
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Edit user message
                        Button(action: {
                            if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                                viewModel.editMessageIndex = idx
                            }
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: - Attached Image Preview
    // Thumbnail above input bar. Tap to view full size. X to remove.

    private var attachedImagePreview: some View {
        HStack {
            Spacer()
            if let image = viewModel.attachedImage {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                        )
                        .onTapGesture { showingAttachmentPreview = true }
                        .popover(isPresented: $showingAttachmentPreview, arrowEdge: .top) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 560, maxHeight: 480)
                                .padding(12)
                        }

                    // Remove attachment
                    Button(action: { viewModel.attachedImage = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 7, y: -7)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBarContainer: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Take Screenshot") { viewModel.attachScreenshot() }
                Button("Attach File…")    { viewModel.attachFile() }
            } label: {
                Image(systemName: viewModel.attachedImage == nil ? "plus" : "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(viewModel.attachedImage == nil
                                     ? Color.white.opacity(0.75)
                                     : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.isLoading)

            ZStack(alignment: .leading) {
                if viewModel.inputText.isEmpty && !viewModel.isRecording {
                    Text("Ask Gemini")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .allowsHitTesting(false)
                } else if viewModel.inputText.isEmpty && viewModel.isRecording {
                    Text("Listening...")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
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

            Button(action: toggleModel) {
                Text(modelLabel)
                    .id(modelLabel)
                    .transition(.opacity)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .keyboardShortcut(.tab, modifiers: .shift)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedModel)

            Button(action: { viewModel.toggleRecording() }) {
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(viewModel.isRecording ? Color.red : Color.white.opacity(0.60))
                    .frame(width: 28, height: 28)
                    .scaleEffect(viewModel.isRecording ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: viewModel.isRecording)
            }
            .buttonStyle(.plain)

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 30, height: 30)
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    private var modelLabel: String {
        selectedModel.contains("flash") ? "Flash" : "Pro"
    }

    private func toggleModel() {
        if selectedModel.contains("flash") {
            selectedModel = "gemini-3.1-pro-preview"
        } else {
            selectedModel = "gemini-3.1-flash-lite-preview"
        }
    }

    private var sendButton: some View {
        Button(action: { viewModel.send() }) {
            Group {
                if emptyInput {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                }
            }
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
