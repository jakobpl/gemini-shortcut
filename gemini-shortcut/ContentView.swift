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
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
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
        ZStack(alignment: .bottom) {
            messageList
                .padding(.bottom, 82)
                .offset(y: contentAppeared ? 0 : 22)
                .opacity(contentAppeared ? 1 : 0)

            VStack(spacing: 0) {
                if !viewModel.attachedImages.isEmpty {
                    attachedCarouselPreview
                        .offset(y: contentAppeared ? 0 : 10)
                        .opacity(contentAppeared ? 1 : 0)
                }

                inputBarContainer
            }
            .offset(y: (inputAppeared && inputBarVisible) ? 0 : 100)
            .opacity((inputAppeared && inputBarVisible) ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: inputBarVisible)
        }
        .frame(minWidth: 580, maxWidth: 580, minHeight: 60, maxHeight: .infinity)
        .onAppear {
            NotificationCenter.default.post(name: .geminiFocusInput, object: nil)
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                contentAppeared = true
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75).delay(0.08)) {
                inputAppeared = true
            }
            updateHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .geminiPanelDidShow)) { _ in
            NotificationCenter.default.post(name: .geminiFocusInput, object: nil)
            updateHeight()
        }
        .onChange(of: viewModel.messages.count) { _, _ in updateHeight() }
        .onChange(of: viewModel.isLoading) { _, _ in updateHeight() }
        .onChange(of: viewModel.attachedImages) { _, _ in updateHeight() }
        .onChange(of: viewModel.messages) { _, _ in viewModel.saveMessages() }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        if !(message.role == .model && message.text.isEmpty && message.isStreaming) {
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
                    }

                    if showThinkingIndicator {
                        HStack(spacing: 8) {
                            SpinnerView()
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .padding(.bottom, 82)
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
                    let delta = offset - lastScrollOffset
                    // Ignore minor jitter; require a few pixels of movement
                    if delta < -6 {
                        // scrolling down (content moves up) — reveal input
                        if !inputBarVisible {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                inputBarVisible = true
                            }
                        }
                        lastScrollOffset = offset
                    } else if delta > 6 {
                        // scrolling up — hide input
                        if inputBarVisible {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                inputBarVisible = false
                            }
                        }
                        lastScrollOffset = offset
                    }
                }
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
        let isLatestUser = message.role == .user
            && message.id == viewModel.messages.last(where: { $0.role == .user })?.id
        return VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                if message.role == .user { Spacer(minLength: 60) }

                let bubbleContent = VStack(alignment: message.role == .model ? .leading : .trailing, spacing: 8) {
                    // User-attached images
                    ForEach(message.images.indices, id: \.self) { idx in
                        Image(nsImage: message.images[idx])
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Text / code blocks
                    if !message.text.isEmpty {
                        if message.role == .model {
                            MessageContentView(text: message.text, isStreaming: message.isStreaming)
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

            // Action buttons — always take space, fade in/out on hover
            HStack(spacing: 8) {
                if message.role == .model {
                    Button(action: {
                        var msg = message
                        msg.rating = msg.rating == .positive ? nil : .positive
                        if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                            viewModel.messages[idx] = msg
                        }
                    }) {
                        Image(systemName: message.rating == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(message.rating == .positive ? Color.accentColor : Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        var msg = message
                        msg.rating = msg.rating == .negative ? nil : .negative
                        if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                            viewModel.messages[idx] = msg
                        }
                    }) {
                        Image(systemName: message.rating == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(message.rating == .negative ? Color.accentColor : Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    if isLatestUser {
                        EditButton(for: message)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
    }

    private func EditButton(for message: ChatMessage) -> some View {
        Button(action: {
            if let idx = viewModel.messages.firstIndex(where: { $0.id == message.id }) {
                viewModel.editMessageIndex = idx
            }
        }) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attached Images Carousel
    // Horizontal scrolling carousel with remove buttons

    private var attachedCarouselPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachedImages.indices, id: \.self) { idx in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: viewModel.attachedImages[idx])
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
                                Image(nsImage: viewModel.attachedImages[idx])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 560, maxHeight: 480)
                                    .padding(12)
                            }

                        Button(action: { viewModel.attachedImages.remove(at: idx) }) {
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
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 90)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBarContainer: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Take Screenshot") { viewModel.attachScreenshot() }
                Button("Screenshot Region…") { viewModel.attachRegionScreenshot() }
                Button("Attach File…")    { viewModel.attachFile() }
            } label: {
                Image(systemName: !viewModel.attachedImages.isEmpty ? "plus.circle.fill" : "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(!viewModel.attachedImages.isEmpty
                                     ? Color.accentColor
                                     : Color.white.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.isLoading)

            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty && !viewModel.isRecording {
                    Text("Ask Gemini")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                } else if viewModel.inputText.isEmpty && viewModel.isRecording {
                    Text("Listening...")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
                ChatInputField(text: $viewModel.inputText) {
                    viewModel.send()
                    NotificationCenter.default.post(name: .geminiFocusInput, object: nil)
                }
                .frame(height: inputFieldHeight)
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
                Button(action: { viewModel.cancelStreaming() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
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
        selectedModel.contains("flash") ? "flash" : "pro"
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
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(emptyInput ? 0.35 : 0.85))
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(emptyInput)
        .animation(.easeInOut(duration: 0.15), value: emptyInput)
    }

    private var emptyInput: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var inputFieldHeight: CGFloat {
        let explicitLines = viewModel.inputText.reduce(into: 1) { count, c in
            if c == "\n" { count += 1 }
        }
        let wrappedLines = max(1, Int(ceil(Double(viewModel.inputText.count) / 60.0)))
        let lines = max(explicitLines, wrappedLines)
        let lineHeight: CGFloat = 18
        return min(CGFloat(lines) * lineHeight + 4, 120)
    }

    private func updateHeight() {
        let hasContent = !viewModel.messages.isEmpty || viewModel.isLoading || !viewModel.attachedImages.isEmpty
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
