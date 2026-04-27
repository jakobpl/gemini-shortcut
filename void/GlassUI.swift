import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - GlassUI
// Shared glass-themed components used by ContentView and SettingsView.

// MARK: - Window Drag Bar

struct WindowDragBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragBarView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Spinning Arc Loader

struct SpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Reveal Blur Text Field

struct RevealBlurTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .blur(radius: (isFocused || isHovered || text.isEmpty) ? 0 : 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.35 : 0.08), lineWidth: 0.8)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Chat Input (multi-line, Enter=submit, Shift+Enter=newline)

struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none

        let tv = SubmitTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textColor = .white
        tv.insertionPointColor = NSColor(white: 1, alpha: 0.95)
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainer?.widthTracksTextView = true
        tv.onSubmit = onSubmit

        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? SubmitTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        tv.onSubmit = onSubmit
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField
        weak var textView: SubmitTextView?

        init(_ parent: ChatInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            // Notify the panel so it can resize when the input grows
            let height = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
            NotificationCenter.default.post(name: .geminiInputHeightChanged, object: height)
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    private var notifToken: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
            if notifToken == nil {
                notifToken = NotificationCenter.default.addObserver(
                    forName: .geminiFocusInput,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.window?.makeFirstResponder(self)
                }
            }
        } else if let token = notifToken {
            NotificationCenter.default.removeObserver(token)
            notifToken = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        // Return (36) or numpad Enter (76). Shift = newline, plain = submit.
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) {
                super.insertNewline(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            NotificationCenter.default.post(name: .geminiPasteImage, object: image)
            return
        }
        super.paste(sender)
    }
}

extension Notification.Name {
    static let geminiFocusInput = Notification.Name("GeminiFocusInput")
    static let geminiInputHeightChanged = Notification.Name("GeminiInputHeightChanged")
    static let geminiPasteImage = Notification.Name("GeminiPasteImage")
}

// MARK: - Selectable Bubble Text (AppKit-backed)

struct SelectableBubbleText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = BubbleSelectableScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.contentView = BubbleSelectableClipView()

        let tv = BubbleSelectableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NSColor.white.withAlphaComponent(0.92)
        tv.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.string = text

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? BubbleSelectableTextView else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let tv = nsView.documentView as? BubbleSelectableTextView else { return nil }

        // ProposedViewSize can be nil/inf during layout probes; clamp to a sane finite width.
        let proposedWidth = proposal.width ?? 320
        let targetWidth = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : 320

        if tv.frame.width != targetWidth {
            tv.frame.size.width = targetWidth
        }
        tv.textContainer?.containerSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        let usedHeight = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
        let textHeight = ceil(usedHeight + (tv.textContainerInset.height * 2))

        return CGSize(width: targetWidth, height: max(20, textHeight))
    }
}

struct SelectableMarkdownBubbleText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = BubbleSelectableScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.contentView = BubbleSelectableClipView()

        let tv = BubbleSelectableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textStorage?.setAttributedString(makeMarkdownAttributedString(from: text))

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? BubbleSelectableTextView else { return }
        let next = makeMarkdownAttributedString(from: text)
        tv.textStorage?.setAttributedString(next)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let tv = nsView.documentView as? BubbleSelectableTextView else { return nil }

        // ProposedViewSize can be nil/inf during layout probes; clamp to a sane finite width.
        let proposedWidth = proposal.width ?? 320
        let targetWidth = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : 320

        if tv.frame.width != targetWidth {
            tv.frame.size.width = targetWidth
        }
        tv.textContainer?.containerSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        let usedHeight = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
        let textHeight = ceil(usedHeight + (tv.textContainerInset.height * 2))

        return CGSize(width: targetWidth, height: max(20, textHeight))
    }

    private func makeMarkdownAttributedString(from source: String) -> NSAttributedString {
        let base = NSMutableAttributedString(string: source, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .font: NSFont.systemFont(ofSize: 14, weight: .regular)
        ])

        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return base
        }

        var parsedStyled = parsed
        parsedStyled.foregroundColor = .white.opacity(0.92)
        parsedStyled.font = .system(.body, design: .rounded)

        // Keep inline code readable in a monospace face.
        for run in parsedStyled.runs where run.inlinePresentationIntent?.contains(.code) == true {
            parsedStyled[run.range].font = .system(.callout, design: .monospaced)
        }

        if let nsAttr = try? NSAttributedString(parsedStyled, including: \.appKit) {
            let ns = NSMutableAttributedString(attributedString: nsAttr)
            let full = NSRange(location: 0, length: ns.length)
            ns.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.92), range: full)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            ns.addAttribute(.paragraphStyle, value: paragraph, range: full)
            return ns
        }

        return base
    }
}

private final class BubbleSelectableTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class BubbleSelectableClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class BubbleSelectableScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Glass Text Editor

struct GlassTextEditor: View {
    var placeholder: String = ""
    @Binding var text: String
    var height: CGFloat = 80
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(height: height)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.35 : 0.08), lineWidth: 0.8)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Syntax Highlighter

func syntaxHighlight(code: String, language: String) -> Text {
    let language = language.lowercased()

    let keywords: [String]
    let stringPatterns: [String]
    let numberPattern: String?
    let commentPatterns: [(pattern: String, isMultiline: Bool)]
    let typePattern: String?
    let functionPattern: String?

    switch language {
    case "swift":
        keywords = ["func", "let", "var", "if", "else", "for", "while", "return", "class", "struct", "enum", "extension", "protocol", "import", "guard", "do", "try", "catch", "throw", "async", "await"]
        stringPatterns = ["\"[^\"]*\"", "\"\"\"[^\"]*\"\"\""]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "//[^\n]*", isMultiline: false), (pattern: "/\\*[\\s\\S]*?\\*/", isMultiline: true)]
        typePattern = "\\b[A-Z][a-zA-Z0-9]*\\b"
        functionPattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("

    case "c":
        keywords = ["int", "void", "return", "if", "else", "for", "while", "struct", "typedef", "const", "static", "include", "define", "char", "float", "double", "long", "unsigned"]
        stringPatterns = ["\"[^\"]*\""]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "//[^\n]*", isMultiline: false), (pattern: "/\\*[\\s\\S]*?\\*/", isMultiline: true)]
        typePattern = "\\b[A-Z][a-zA-Z0-9]*\\b"
        functionPattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("

    case "cpp", "c++":
        keywords = ["int", "void", "return", "if", "else", "for", "while", "class", "struct", "namespace", "template", "public", "private", "protected", "const", "auto", "nullptr", "new", "delete", "bool", "typedef", "include", "define", "char", "float", "double"]
        stringPatterns = ["\"[^\"]*\""]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "//[^\n]*", isMultiline: false), (pattern: "/\\*[\\s\\S]*?\\*/", isMultiline: true)]
        typePattern = "\\b[A-Z][a-zA-Z0-9]*\\b"
        functionPattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("

    case "html":
        keywords = []
        stringPatterns = ["\"[^\"]*\"", "'[^']*'"]
        numberPattern = nil
        commentPatterns = [(pattern: "<!--[\\s\\S]*?-->", isMultiline: true)]
        typePattern = nil
        functionPattern = nil

    case "css":
        keywords = ["color", "display", "background", "margin", "padding", "border", "width", "height", "font", "text", "position", "top", "left", "right", "bottom"]
        stringPatterns = ["\"[^\"]*\"", "'[^']*'"]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "/\\*[\\s\\S]*?\\*/", isMultiline: true)]
        typePattern = nil
        functionPattern = nil

    case "python":
        keywords = ["def", "class", "if", "else", "elif", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "pass", "break", "continue"]
        stringPatterns = ["\"[^\"]*\"", "'[^']*'", "\"\"\"[^\"]*\"\"\"", "'''[^']*'''"]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "#[^\n]*", isMultiline: false)]
        typePattern = nil
        functionPattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("

    case "javascript", "typescript", "js", "ts":
        keywords = ["function", "const", "let", "var", "if", "else", "for", "while", "return", "class", "import", "export", "async", "await", "try", "catch", "throw", "new"]
        stringPatterns = ["\"[^\"]*\"", "'[^']*'", "`[^`]*`"]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "//[^\n]*", isMultiline: false), (pattern: "/\\*[\\s\\S]*?\\*/", isMultiline: true)]
        typePattern = "\\b[A-Z][a-zA-Z0-9]*\\b"
        functionPattern = "\\b([a-z_][a-zA-Z0-9_]*)\\s*\\("

    case "bash", "sh":
        keywords = ["if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "export", "local"]
        stringPatterns = ["\"[^\"]*\"", "'[^']*'"]
        numberPattern = "\\b[0-9]+(\\.[0-9]+)?\\b"
        commentPatterns = [(pattern: "#[^\n]*", isMultiline: false)]
        typePattern = nil
        functionPattern = nil

    default:
        return Text(code).foregroundStyle(monokaiDefaultTextColor)
    }

    let nsString = code as NSString
    let nsRange = NSRange(location: 0, length: nsString.length)

    var coloredRanges: [(range: NSRange, color: Color)] = []

    // Monokai palette
    let keywordColor  = Color(red: 0.976, green: 0.149, blue: 0.447) // #F92672
    let stringColor   = Color(red: 0.902, green: 0.859, blue: 0.455) // #E6DB74
    let numberColor   = Color(red: 0.682, green: 0.506, blue: 1.000) // #AE81FF
    let commentColor  = Color(red: 0.459, green: 0.443, blue: 0.369) // #75715E
    let typeColor     = Color(red: 0.400, green: 0.851, blue: 0.937) // #66D9EF
    let functionColor = Color(red: 0.651, green: 0.886, blue: 0.180) // #A6E22E

    for comment in commentPatterns {
        if let regex = try? NSRegularExpression(pattern: comment.pattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                coloredRanges.append((range: match.range, color: commentColor))
            }
        }
    }

    for pattern in stringPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                coloredRanges.append((range: match.range, color: stringColor))
            }
        }
    }

    for keyword in keywords {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                coloredRanges.append((range: match.range, color: keywordColor))
            }
        }
    }

    if let numberPattern = numberPattern {
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                coloredRanges.append((range: match.range, color: numberColor))
            }
        }
    }

    if let typePattern = typePattern {
        if let regex = try? NSRegularExpression(pattern: typePattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                coloredRanges.append((range: match.range, color: typeColor))
            }
        }
    }

    if let functionPattern = functionPattern {
        if let regex = try? NSRegularExpression(pattern: functionPattern, options: []) {
            for match in regex.matches(in: code, options: [], range: nsRange) {
                if match.numberOfRanges > 1 {
                    coloredRanges.append((range: match.range(at: 1), color: functionColor))
                }
            }
        }
    }

    var result = Text("")
    var lastEnd = 0

    let sortedRanges = coloredRanges.sorted { $0.range.location < $1.range.location }

    for (range, color) in sortedRanges {
        if range.location > lastEnd {
            let plainRange = NSRange(location: lastEnd, length: range.location - lastEnd)
            let plainText = nsString.substring(with: plainRange)
            result = result + Text(plainText).foregroundStyle(monokaiDefaultTextColor)
        }

        let coloredText = nsString.substring(with: range)
        result = result + Text(coloredText).foregroundStyle(color)

        lastEnd = range.location + range.length
    }

    if lastEnd < code.count {
        let remaining = nsString.substring(with: NSRange(location: lastEnd, length: code.count - lastEnd))
        result = result + Text(remaining).foregroundStyle(monokaiDefaultTextColor)
    }

    return result
}

// Monokai default foreground (#F8F8F2) and background (#272822)
let monokaiDefaultTextColor = Color(red: 0.973, green: 0.973, blue: 0.949)
let monokaiBackgroundColor  = Color(red: 0.153, green: 0.157, blue: 0.133)

// MARK: - Code Block View
// Renders a fenced code block with IDE-style chrome: language label, copy button,
// dark background, monospaced font, and horizontal scroll for long lines.

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar — language label + copy
            HStack(spacing: 8) {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(copied ? 0.9 : 0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.30))

            Divider()
                .background(Color.white.opacity(0.06))

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                syntaxHighlight(code: code, language: language)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(monokaiBackgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.trimmingCharacters(in: .newlines), forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - Message Content View
// Splits raw markdown into fenced code blocks and plain-text spans,
// then renders each with full block-level markdown support.

struct MessageSegment: Identifiable {
    let id = UUID()
    enum Kind {
        case text(String)
        case code(language: String, code: String)
    }
    let kind: Kind
}

func parseMessageSegments(_ raw: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    let pattern = "```([\\w]*)\n?([\\s\\S]*?)```"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [MessageSegment(kind: .text(raw))]
    }

    let ns = raw as NSString
    let fullRange = NSRange(location: 0, length: ns.length)
    var cursor = 0

    for match in regex.matches(in: raw, range: fullRange) {
        let preLen = match.range.location - cursor
        if preLen > 0 {
            let pre = ns.substring(with: NSRange(location: cursor, length: preLen))
            if !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(MessageSegment(kind: .text(pre)))
            }
        }
        let lang = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : ""
        let code = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : ""
        segments.append(MessageSegment(kind: .code(language: lang, code: code)))
        cursor = match.range.location + match.range.length
    }

    if cursor < ns.length {
        let tail = ns.substring(from: cursor)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(MessageSegment(kind: .text(tail)))
        }
    }
    if segments.isEmpty { segments.append(MessageSegment(kind: .text(raw))) }
    return segments
}

// MARK: - Block-level Markdown Parser

enum TextBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletItem(text: String)
    case numberedItem(number: Int, text: String)
    case blockquote(text: String)
    case horizontalRule
}

func parseTextBlocks(_ raw: String) -> [TextBlock] {
    let lines = raw.components(separatedBy: "\n")
    var blocks: [TextBlock] = []
    var pendingLines: [String] = []

    func flushPending() {
        let joined = pendingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pendingLines.removeAll()
        if !joined.isEmpty { blocks.append(.paragraph(text: joined)) }
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { flushPending(); continue }

        // Horizontal rule: ---, ***, or ___
        if trimmed.range(of: "^(---+|\\*\\*\\*+|___+)$", options: .regularExpression) != nil {
            flushPending(); blocks.append(.horizontalRule); continue
        }

        // Headings
        if trimmed.hasPrefix("### ") {
            flushPending(); blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4)))); continue
        }
        if trimmed.hasPrefix("## ") {
            flushPending(); blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3)))); continue
        }
        if trimmed.hasPrefix("# ") {
            flushPending(); blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2)))); continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") {
            flushPending(); blocks.append(.blockquote(text: String(trimmed.dropFirst(2)))); continue
        }

        // Bullet: "- " or "• "
        if trimmed.hasPrefix("- ") {
            flushPending(); blocks.append(.bulletItem(text: String(trimmed.dropFirst(2)))); continue
        }
        if trimmed.hasPrefix("• ") {
            flushPending(); blocks.append(.bulletItem(text: String(trimmed.dropFirst(2)))); continue
        }
        // Bullet: "* " or "*  " (1–2 stars then whitespace — Gemini style)
        if let r = trimmed.range(of: "^\\*{1,2}\\s+", options: .regularExpression) {
            flushPending(); blocks.append(.bulletItem(text: String(trimmed[r.upperBound...]))); continue
        }

        // Numbered list: "1. text"
        if let r = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) {
            let numStr = String(trimmed[r].dropLast(2))
            let num = Int(numStr) ?? 1
            let text = String(trimmed[r.upperBound...])
            flushPending(); blocks.append(.numberedItem(number: num, text: text)); continue
        }

        pendingLines.append(line)
    }

    flushPending()
    return blocks.isEmpty ? [.paragraph(text: raw)] : blocks
}

// MARK: - Math Rendering
// Renders LaTeX-style math (fractions, sqrt, Greek letters, super/subscripts,
// common symbols) as Unicode / SwiftUI views for readability.

struct FractionView: View {
    let numerator: String
    let denominator: String

    var body: some View {
        VStack(spacing: 2) {
            Text(renderMathInline(numerator))
                .font(.system(.body, design: .serif, weight: .medium).italic())
                .foregroundStyle(Color.white.opacity(0.95))
            Rectangle()
                .fill(Color.white.opacity(0.65))
                .frame(height: 1.2)
            Text(renderMathInline(denominator))
                .font(.system(.body, design: .serif, weight: .medium).italic())
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

struct SqrtView: View {
    let content: String

    var body: some View {
        HStack(spacing: 0) {
            Text("√")
                .font(.system(.title2, design: .serif, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.95))
            Text(renderMathInline(content))
                .font(.system(.body, design: .serif, weight: .medium).italic())
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.top, 2)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.65))
                        .frame(height: 1.2)
                        .padding(.horizontal, -1),
                    alignment: .top
                )
                .padding(.top, 2)
        }
        .fixedSize()
    }
}

// Latin → Greek / symbol replacements applied inside math mode.
private let latexSymbolMap: [String: String] = [
    // Greek lowercase
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
    "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
    "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
    "chi": "χ", "psi": "ψ", "omega": "ω", "varepsilon": "ε", "varphi": "ϕ",
    // Greek uppercase
    "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
    "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
    "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Pi": "Π",
    "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
    "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω",
    // Operators / relations
    "times": "×", "div": "÷", "cdot": "·", "pm": "±", "mp": "∓",
    "neq": "≠", "ne": "≠", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥",
    "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝",
    "infty": "∞", "partial": "∂", "nabla": "∇",
    "sum": "∑", "prod": "∏", "int": "∫", "oint": "∮",
    "in": "∈", "notin": "∉", "subset": "⊂", "supset": "⊃",
    "cup": "∪", "cap": "∩", "emptyset": "∅", "forall": "∀", "exists": "∃",
    "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔",
    "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔",
    "ldots": "…", "cdots": "⋯", "dots": "…",
    "degree": "°", "prime": "′",
]

private let superscriptMap: [Character: Character] = [
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
    "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
    "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
    "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
    "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ",
    "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
    "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
]

private let subscriptMap: [Character: Character] = [
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅",
    "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
    "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
    "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
    "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
]

// Convert a short string of digits/letters to Unicode sub/superscript where possible.
private func toSuperscript(_ s: String) -> String {
    String(s.map { superscriptMap[$0] ?? $0 })
}
private func toSubscript(_ s: String) -> String {
    String(s.map { subscriptMap[$0] ?? $0 })
}

// Render inline math: replaces `\symbol`, `^{...}`, `_{...}` within a string.
// Fractions and sqrt are split out separately because they need 2-D layout.
func renderMathInline(_ raw: String) -> String {
    var s = raw

    // Replace \frac{a}{b} with (a)/(b) using Unicode rendering for nested content
    let fracPattern = #"\\frac\{([^{}]*)\}\{([^{}]*)\}"#
    if let fracRegex = try? NSRegularExpression(pattern: fracPattern) {
        let ns = s as NSString
        let matches = fracRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let num = ns.substring(with: m.range(at: 1))
            let den = ns.substring(with: m.range(at: 2))
            let replacement = "(\(renderMathInline(num)))/(\(renderMathInline(den)))"
            s = ns.replacingCharacters(in: m.range, with: replacement)
        }
    }

    // Replace \sqrt{x} with √x
    let sqrtPattern = #"\\sqrt\{([^{}]*)\}"#
    if let sqrtRegex = try? NSRegularExpression(pattern: sqrtPattern) {
        let ns = s as NSString
        let matches = sqrtRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let content = ns.substring(with: m.range(at: 1))
            let replacement = "√(\(renderMathInline(content)))"
            s = ns.replacingCharacters(in: m.range, with: replacement)
        }
    }

    // \symbol tokens → unicode
    let tokenRegex = try? NSRegularExpression(pattern: "\\\\([A-Za-z]+)")
    if let tokenRegex {
        let ns = s as NSString
        let matches = tokenRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let name = ns.substring(with: m.range(at: 1))
            if let sym = latexSymbolMap[name] {
                s = (s as NSString).replacingCharacters(in: m.range, with: sym)
            }
        }
    }

    // Superscripts: ^{...} or ^x (single char)
    s = replaceMathScript(in: s, marker: "^", mapFn: toSuperscript)
    // Subscripts: _{...} or _x
    s = replaceMathScript(in: s, marker: "_", mapFn: toSubscript)

    return s
}

private func replaceMathScript(in text: String, marker: String, mapFn: (String) -> String) -> String {
    var result = ""
    var i = text.startIndex
    while i < text.endIndex {
        let c = text[i]
        if String(c) == marker {
            let next = text.index(after: i)
            if next < text.endIndex && text[next] == "{" {
                // read until matching brace
                if let close = text[next...].firstIndex(of: "}") {
                    let inner = String(text[text.index(after: next)..<close])
                    result += mapFn(inner)
                    i = text.index(after: close)
                    continue
                }
            } else if next < text.endIndex {
                let inner = String(text[next])
                result += mapFn(inner)
                i = text.index(after: next)
                continue
            }
        }
        result.append(c)
        i = text.index(after: i)
    }
    return result
}

// MARK: - Math Text Segment Parser

enum TextSegment: Identifiable {
    case text(String)
    case inlineMath(String)
    case blockMath(String)

    var id: String { UUID().uuidString }
}

func parseTextSegmentsWithMath(_ raw: String) -> [TextSegment] {
    var segments: [TextSegment] = []
    let pattern = "\\$\\$([\\s\\S]*?)\\$\\$|\\$([^$\n]+?)\\$"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [.text(raw)]
    }

    let ns = raw as NSString
    let fullRange = NSRange(location: 0, length: ns.length)
    var cursor = 0

    for match in regex.matches(in: raw, range: fullRange) {
        let preLen = match.range.location - cursor
        if preLen > 0 {
            let pre = ns.substring(with: NSRange(location: cursor, length: preLen))
            if !pre.isEmpty {
                segments.append(.text(pre))
            }
        }

        if match.range(at: 1).location != NSNotFound {
            let inner = ns.substring(with: match.range(at: 1))
            segments.append(.blockMath(inner))
        } else if match.range(at: 2).location != NSNotFound {
            let inner = ns.substring(with: match.range(at: 2))
            segments.append(.inlineMath(inner))
        }

        cursor = match.range.location + match.range.length
    }

    if cursor < ns.length {
        let tail = ns.substring(from: cursor)
        if !tail.isEmpty {
            segments.append(.text(tail))
        }
    }

    return segments.isEmpty ? [.text(raw)] : segments
}

// MARK: - Math Expression View
// Renders LaTeX math locally using Unicode symbols and custom 2-D views.

struct MathExpressionView: View {
    let latex: String
    let isBlock: Bool

    var body: some View {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)

        Group {
            if let fraction = parseFraction(trimmed) {
                FractionView(numerator: fraction.num, denominator: fraction.den)
            } else if let sqrtContent = parseSqrt(trimmed) {
                SqrtView(content: sqrtContent)
            } else {
                Text(renderMathInline(trimmed))
                    .font(.system(.body, design: .serif, weight: .medium).italic())
                    .foregroundStyle(Color.white.opacity(0.95))
            }
        }
        .padding(.vertical, isBlock ? 8 : 2)
        .frame(maxWidth: isBlock ? .infinity : nil, alignment: isBlock ? .center : .leading)
    }
}

private func parseFraction(_ latex: String) -> (num: String, den: String)? {
    guard latex.hasPrefix(#"\frac"#) else { return nil }

    var index = latex.index(latex.startIndex, offsetBy: 5)

    while index < latex.endIndex && latex[index].isWhitespace {
        index = latex.index(after: index)
    }

    guard index < latex.endIndex && latex[index] == "{" else { return nil }
    index = latex.index(after: index)

    var braceDepth = 1
    let numStart = index
    while index < latex.endIndex && braceDepth > 0 {
        if latex[index] == "{" { braceDepth += 1 }
        else if latex[index] == "}" { braceDepth -= 1 }
        if braceDepth > 0 { index = latex.index(after: index) }
    }
    guard braceDepth == 0 else { return nil }
    let numerator = String(latex[numStart..<index])
    index = latex.index(after: index)

    while index < latex.endIndex && latex[index].isWhitespace {
        index = latex.index(after: index)
    }

    guard index < latex.endIndex && latex[index] == "{" else { return nil }
    index = latex.index(after: index)

    braceDepth = 1
    let denStart = index
    while index < latex.endIndex && braceDepth > 0 {
        if latex[index] == "{" { braceDepth += 1 }
        else if latex[index] == "}" { braceDepth -= 1 }
        if braceDepth > 0 { index = latex.index(after: index) }
    }
    guard braceDepth == 0 else { return nil }
    let denominator = String(latex[denStart..<index])

    return (numerator, denominator)
}

private func parseSqrt(_ latex: String) -> String? {
    guard latex.hasPrefix(#"\sqrt"#) else { return nil }

    var index = latex.index(latex.startIndex, offsetBy: 5)

    while index < latex.endIndex && latex[index].isWhitespace {
        index = latex.index(after: index)
    }

    guard index < latex.endIndex && latex[index] == "{" else { return nil }
    index = latex.index(after: index)

    var braceDepth = 1
    let contentStart = index
    while index < latex.endIndex && braceDepth > 0 {
        if latex[index] == "{" { braceDepth += 1 }
        else if latex[index] == "}" { braceDepth -= 1 }
        if braceDepth > 0 { index = latex.index(after: index) }
    }
    guard braceDepth == 0 else { return nil }

    return String(latex[contentStart..<index])
}

// MARK: - Markdown Text Blocks View

struct MarkdownTextBlocksView: View {
    let text: String
    var animate: Bool = false

    var body: some View {
        let blocks = parseTextBlocks(text)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                Group {
                    if animate && idx == blocks.count - 1 {
                        LeftToRightReveal(duration: 0.5) {
                            blockView(for: block)
                        }
                        .id("streaming-\(idx)-\(blockIdentity(block))")
                    } else {
                        blockView(for: block)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func blockIdentity(_ block: TextBlock) -> String {
        switch block {
        case .heading(let l, let t): return "h\(l):\(t.prefix(12))"
        case .paragraph(let t): return "p:\(t.prefix(12))"
        case .bulletItem(let t): return "b:\(t.prefix(12))"
        case .numberedItem(_, let t): return "n:\(t.prefix(12))"
        case .blockquote(let t): return "q:\(t.prefix(12))"
        case .horizontalRule: return "hr"
        }
    }

    @ViewBuilder
    private func blockView(for block: TextBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text, font: headingFont(level))
                .padding(.top, level == 1 ? 6 : 3)

        case .paragraph(let text):
            inlineText(text, font: .system(.body, design: .rounded))

        case .bulletItem(let text):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.top, 1)
                inlineText(text, font: .system(.body, design: .rounded))
            }

        case .numberedItem(let n, let text):
            HStack(alignment: .top, spacing: 7) {
                Text("\(n).")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(minWidth: 22, alignment: .trailing)
                    .padding(.top, 1)
                inlineText(text, font: .system(.body, design: .rounded))
            }

        case .blockquote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3)
                inlineText(text, font: .system(.body, design: .rounded))
                    .opacity(0.78)
            }

        case .horizontalRule:
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.75)
                .padding(.vertical, 3)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(.title2, design: .rounded, weight: .bold)
        case 2: return .system(.title3, design: .rounded, weight: .semibold)
        default: return .system(.headline, design: .rounded, weight: .semibold)
        }
    }

    private func inlineText(_ rawText: String, font: Font) -> some View {
        let segments = parseTextSegmentsWithMath(rawText)

        let hasBlockMath = segments.contains { 
            if case .blockMath = $0 { return true }
            return false
        }

        if !hasBlockMath {
            return AnyView(
                concatenate(segments, font: font)
                    .lineSpacing(3)
            )
        }

        var rows: [[TextSegment]] = []
        var currentTextRow: [TextSegment] = []

        for segment in segments {
            switch segment {
            case .text, .inlineMath:
                currentTextRow.append(segment)
            case .blockMath:
                if !currentTextRow.isEmpty {
                    rows.append(currentTextRow)
                    currentTextRow = []
                }
                rows.append([segment])
            }
        }
        if !currentTextRow.isEmpty {
            rows.append(currentTextRow)
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.count == 1, case .blockMath(let math) = row[0] {
                        MathExpressionView(latex: math, isBlock: true)
                    } else {
                        concatenate(row, font: font)
                            .lineSpacing(3)
                    }
                }
            }
        )
    }

    private func concatenate(_ segments: [TextSegment], font: Font) -> Text {
        var resultText = Text("")
        var first = true

        for segment in segments {
            let nextText: Text
            switch segment {
            case .text(let t):
                if let attrStr = markdownAttributed(t, font: font) {
                    nextText = Text(attrStr).foregroundColor(.white.opacity(0.92))
                } else {
                    nextText = Text(t).font(font).foregroundColor(.white.opacity(0.92))
                }
            case .inlineMath(let math):
                let trimmed = math.trimmingCharacters(in: .whitespacesAndNewlines)
                nextText = Text(renderMathInline(trimmed))
                    .font(.system(.body, design: .serif, weight: .medium).italic())
                    .foregroundColor(.white.opacity(0.95))
            case .blockMath(let math):
                let trimmed = math.trimmingCharacters(in: .whitespacesAndNewlines)
                nextText = Text("\n\n" + renderMathInline(trimmed) + "\n\n")
                    .font(.system(.title3, design: .serif, weight: .medium).italic())
                    .foregroundColor(.white.opacity(0.95))
            }
            if first {
                resultText = nextText
                first = false
            } else {
                resultText = resultText + nextText
            }
        }
        return resultText
    }

    private func markdownAttributed(_ text: String, font: Font) -> AttributedString? {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var str = try? AttributedString(markdown: text, options: opts) else { return nil }
        str.font = font
        // Style inline code with monospaced font
        for run in str.runs where run.inlinePresentationIntent?.contains(.code) == true {
            str[run.range].font = Font.system(.callout, design: .monospaced)
        }
        return str
    }
}

// MARK: - Message Content View (outer container)

struct MessageContentView: View {
    let text: String
    var isStreaming: Bool = false
    var revealedWordCount: Int = 0

    var body: some View {
        Group {
            if isStreaming {
                StreamingWordRevealText(text: text, revealedWordCount: revealedWordCount)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parseMessageSegments(text)) { segment in
                        switch segment.kind {
                        case .text(let t):
                            MarkdownTextBlocksView(text: t, animate: false)
                        case .code(let lang, let code):
                            CodeBlockView(language: lang, code: code)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct StreamingWordRevealText: View {
    let text: String
    let revealedWordCount: Int

    var body: some View {
        buildRevealText(from: tokenized(text))
            .font(.system(.body, design: .rounded))
            .lineSpacing(3)
            .animation(.easeInOut(duration: 0.18), value: revealedWordCount)
    }

    private func tokenized(_ source: String) -> [(value: String, isWord: Bool)] {
        guard !source.isEmpty else { return [] }
        var tokens: [(String, Bool)] = []
        var current = ""
        var currentIsWord: Bool?

        for ch in source {
            let isWord = !(ch.isWhitespace || ch.isNewline)
            if currentIsWord == nil {
                currentIsWord = isWord
                current.append(ch)
                continue
            }

            if currentIsWord == isWord {
                current.append(ch)
            } else {
                tokens.append((current, currentIsWord ?? false))
                current = String(ch)
                currentIsWord = isWord
            }
        }

        if !current.isEmpty {
            tokens.append((current, currentIsWord ?? false))
        }

        return tokens
    }

    private func buildRevealText(from tokens: [(value: String, isWord: Bool)]) -> Text {
        var result = Text("")
        var visibleWordIndex = 0

        for token in tokens {
            if token.isWord {
                let isVisible = visibleWordIndex < revealedWordCount
                let opacity = isVisible ? 0.92 : 0.20
                result = result + Text(token.value).foregroundColor(.white.opacity(opacity))
                visibleWordIndex += 1
            } else {
                result = result + Text(token.value).foregroundColor(.white.opacity(0.92))
            }
        }

        return result
    }
}

// MARK: - Left-to-right reveal wrapper
// Fades in content from the leading edge to the trailing edge.
// Used for streamed agent responses so each line/block appears elegantly.

struct LeftToRightReveal<Content: View>: View {
    let content: Content
    var duration: Double = 0.45
    var delay: Double = 0
    @State private var progress: CGFloat = 0

    init(duration: Double = 0.45, delay: Double = 0, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.duration = duration
        self.delay = delay
    }

    var body: some View {
        content
            .opacity(progress == 0 ? 0 : 1)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.8),
                            .init(color: .white.opacity(0), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(geo.size.width, 100) * 1.5)
                    .offset(x: -max(geo.size.width, 100) * 1.5 + (progress * max(geo.size.width, 100) * 3))
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    progress = 1.0
                }
            }
    }
}

// MARK: - Window Resize Handles
// Invisible corner/edge regions that let the user resize the borderless panel.

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
    case topEdge, bottomEdge, leftEdge, rightEdge
}

struct WindowResizeHandle: NSViewRepresentable {
    let corner: ResizeCorner

    func makeNSView(context: Context) -> NSView {
        ResizeHandleNSView(corner: corner)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ResizeHandleNSView: NSView {
    let corner: ResizeCorner
    private var initialFrame: NSRect = .zero
    private var initialLocation: NSPoint = .zero

    init(corner: ResizeCorner) {
        self.corner = corner
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        initialFrame = window.frame
        initialLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y

        var newFrame = initialFrame
        let minWidth: CGFloat = 400
        let minHeight: CGFloat = 120

        switch corner {
        case .bottomRight:
            newFrame.size.width = max(minWidth, initialFrame.width + deltaX)
            newFrame.size.height = max(minHeight, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
        case .bottomLeft:
            let newWidth = max(minWidth, initialFrame.width - deltaX)
            newFrame.size.height = max(minHeight, initialFrame.height - deltaY)
            newFrame.origin.x = initialFrame.origin.x + (initialFrame.width - newWidth)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
            newFrame.size.width = newWidth
        case .topRight:
            newFrame.size.width = max(minWidth, initialFrame.width + deltaX)
            newFrame.size.height = max(minHeight, initialFrame.height + deltaY)
        case .topLeft:
            let newWidth = max(minWidth, initialFrame.width - deltaX)
            newFrame.size.height = max(minHeight, initialFrame.height + deltaY)
            newFrame.origin.x = initialFrame.origin.x + (initialFrame.width - newWidth)
            newFrame.size.width = newWidth
        case .topEdge:
            newFrame.size.height = max(minHeight, initialFrame.height + deltaY)
        case .bottomEdge:
            newFrame.size.height = max(minHeight, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
        case .leftEdge:
            let newWidth = max(minWidth, initialFrame.width - deltaX)
            newFrame.origin.x = initialFrame.origin.x + (initialFrame.width - newWidth)
            newFrame.size.width = newWidth
        case .rightEdge:
            newFrame.size.width = max(minWidth, initialFrame.width + deltaX)
        }

        window.setFrame(newFrame, display: true)
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch corner {
        case .leftEdge, .rightEdge:
            cursor = .resizeLeftRight
        case .topEdge, .bottomEdge:
            cursor = .resizeUpDown
        default:
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }
}

// MARK: - Generated Image View
// Displays an AI-generated image with a hoverable download button.

struct GeneratedImageView: View {
    let imageData: Data
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            }

            if isHovering {
                Button(action: saveImage) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(10)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated-image.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? imageData.write(to: url)
        }
    }
}
