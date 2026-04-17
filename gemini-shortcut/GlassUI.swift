import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - GlassUI
// Shared glass-themed components used by ContentView and SettingsView.

// MARK: - Typing Dots Loader

struct TypingDotsView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .scaleEffect(isAnimating && getScale(for: index) > 0 ? getScale(for: index) : 1.0)
                    .opacity(isAnimating ? getOpacity(for: index) : 1.0)
            }
        }
        .frame(width: 24, height: 8)
        .shadow(color: Color.white.opacity(0.3), radius: 2, x: 0, y: 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }

    private func getScale(for index: Int) -> CGFloat {
        switch index {
        case 0: return 1.2
        case 1: return 1.35
        case 2: return 1.2
        default: return 1.0
        }
    }

    private func getOpacity(for index: Int) -> Double {
        switch index {
        case 0: return 0.6
        case 1: return 1.0
        case 2: return 0.6
        default: return 1.0
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
        return Text(code).foregroundStyle(Color.white.opacity(0.90))
    }

    let nsString = code as NSString
    let nsRange = NSRange(location: 0, length: nsString.length)

    var coloredRanges: [(range: NSRange, color: Color)] = []

    let keywordColor = Color(red: 0.78, green: 0.57, blue: 0.92)
    let stringColor = Color(red: 0.97, green: 0.49, blue: 0.42)
    let numberColor = Color(red: 0.53, green: 0.87, blue: 1.0)
    let commentColor = Color(red: 0.33, green: 0.43, blue: 0.46)
    let typeColor = Color(red: 1.0, green: 0.79, blue: 0.42)
    let functionColor = Color(red: 0.51, green: 0.67, blue: 1.0)

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
            result = result + Text(plainText).foregroundStyle(Color.white.opacity(0.90))
        }

        let coloredText = nsString.substring(with: range)
        result = result + Text(coloredText).foregroundStyle(color)

        lastEnd = range.location + range.length
    }

    if lastEnd < code.count {
        let remaining = nsString.substring(with: NSRange(location: lastEnd, length: code.count - lastEnd))
        result = result + Text(remaining).foregroundStyle(Color.white.opacity(0.90))
    }

    return result
}

// MARK: - Code Block View
// Renders a fenced code block with IDE-style chrome: language label, copy button,
// dark background, monospaced font, and horizontal scroll for long lines.

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer()
                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(copied ? 0.85 : 0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))

            Divider()
                .background(Color.white.opacity(0.08))

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                syntaxHighlight(code: code, language: language)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.38))
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

// MARK: - Markdown Text Blocks View

struct MarkdownTextBlocksView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(parseTextBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
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

    @ViewBuilder
    private func inlineText(_ rawText: String, font: Font) -> some View {
        if let attrStr = markdownAttributed(rawText, font: font) {
            Text(attrStr)
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawText)
                .font(font)
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMessageSegments(text)) { segment in
                switch segment.kind {
                case .text(let t):
                    MarkdownTextBlocksView(text: t)
                case .code(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                }
            }
        }
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
