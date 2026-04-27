import SwiftUI

// MARK: - SettingsView
// Shown in a floating NSPanel when the user clicks the menu bar icon.
// Covers: API key, custom system instructions, and feature toggles.
// Model selection is intentionally absent here — use the pill in the chat input bar instead.

struct SettingsView: View {
    // Local state mirrors SettingsManager; autosaved on every change via .onChange
    @State private var apiKey = SettingsManager.shared.apiKey ?? ""
    @State private var customInstructions = SettingsManager.shared.customInstructions
    @State private var toolCalling = SettingsManager.shared.toolCallingEnabled
    @State private var runTerminal = SettingsManager.shared.runTerminalCommandsEnabled
    @State private var workingDir = SettingsManager.shared.workingDirectory

    // Entrance animation state
    @State private var appeared = false
    // Controls close-button visibility (appears on hover)
    @State private var isHovering = false

    let dismiss: () -> Void

    var body: some View {
        ZStack {
            // Tap-outside-to-deselect layer (covers the whole panel, transparent)
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }

            VStack(spacing: 12) {
                // API Key field — blurs when not focused to hide the key visually.
                // Accepts a real AIza… key or "dev" to enable the local mock bypass.
                RevealBlurTextField(placeholder: "API Key", text: $apiKey)

                // Multi-line custom system instructions fed to every Gemini request
                GlassTextEditor(
                    placeholder: "Custom instructions…",
                    text: $customInstructions,
                    height: 72
                )

                // Feature toggles — take effect immediately on next send
                VStack(spacing: 10) {
                    // Enables Gemini function-calling in API requests
                    Toggle("Enable tool calling", isOn: $toolCalling)
                        .toggleStyle(.switch)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))

                    // Allows the run_terminal_command tool to execute shell commands
                    Toggle("Allow terminal commands", isOn: $runTerminal)
                        .toggleStyle(.switch)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))

                    // Working directory for file/command operations
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.50))
                        Text(workingDir.components(separatedBy: "/").last ?? "Desktop")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change…") { pickDirectory() }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            // Entrance: slides up and fades in
            .offset(y: appeared ? 0 : 18)
            .opacity(appeared ? 1 : 0)
            // Autosave on any field change
            .onChange(of: apiKey)             { save() }
            .onChange(of: customInstructions) { save() }
            .onChange(of: toolCalling)        { save() }
            .onChange(of: runTerminal)        { save() }
            .onChange(of: workingDir)         { save() }

            // Close button — top-right, fades in when cursor enters the panel
            closeButton
        }
        .frame(width: 360, height: 310)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.74)) {
                appeared = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
        }
    }

    // MARK: - Close Button
    // Dismisses the settings panel. Visible only while hovering — avoids clutter at rest.

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            Spacer()
        }
        .opacity(isHovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    // MARK: - Persist

    private func save() {
        SettingsManager.shared.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsManager.shared.customInstructions = customInstructions
        SettingsManager.shared.toolCallingEnabled = toolCalling
        SettingsManager.shared.runTerminalCommandsEnabled = runTerminal
        SettingsManager.shared.workingDirectory = workingDir
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Working Directory"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            workingDir = url.path
        }
    }
}
