import SwiftUI

// MARK: - SettingsView
// Shown in a floating NSPanel when the user clicks the menu bar icon.
// Covers: per-provider API keys, custom system instructions, feature toggles,
// panel position, and Ollama configuration.

struct SettingsView: View {
    // Per-provider key editing
    @State private var selectedProviderForKey: ProviderID = SettingsManager.shared.selectedProvider
    @State private var providerKeyText: String = ""

    // Panel position
    @State private var panelAnchor: PanelAnchor = SettingsManager.shared.panelAnchor
    @State private var panelOffsetX: CGFloat = SettingsManager.shared.panelOffsetX
    @State private var panelOffsetY: CGFloat = SettingsManager.shared.panelOffsetY

    // Ollama
    @State private var ollamaURL: String = SettingsManager.shared.ollamaBaseURL
    @State private var ollamaTestResult: String? = nil
    @State private var ollamaTesting = false

    // Existing settings
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

            ScrollView {
                VStack(spacing: 18) {
                    providerKeySection
                    panelPositionSection
                    ollamaSection
                    instructionsSection
                    togglesSection
                    workingDirSection
                    accessibilitySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            // Entrance: slides up and fades in
            .offset(y: appeared ? 0 : 18)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.44, dampingFraction: 0.74), value: appeared)

            // Close button — top-right, fades in when cursor enters the panel
            closeButton
        }
        .frame(width: 380, height: 560)
        .background {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            selectedProviderForKey = SettingsManager.shared.selectedProvider
            providerKeyText = SettingsManager.shared.apiKey(for: selectedProviderForKey) ?? ""
            panelAnchor = SettingsManager.shared.panelAnchor
            panelOffsetX = SettingsManager.shared.panelOffsetX
            panelOffsetY = SettingsManager.shared.panelOffsetY
            ollamaURL = SettingsManager.shared.ollamaBaseURL
            customInstructions = SettingsManager.shared.customInstructions
            toolCalling = SettingsManager.shared.toolCallingEnabled
            runTerminal = SettingsManager.shared.runTerminalCommandsEnabled
            workingDir = SettingsManager.shared.workingDirectory
            withAnimation(.spring(response: 0.44, dampingFraction: 0.74)) {
                appeared = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
        }
    }

    // MARK: - Provider Key Section

    private var providerKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Keys")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Picker("Provider", selection: $selectedProviderForKey) {
                ForEach(ProviderID.allCases) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedProviderForKey) { oldValue, newValue in
                // Save previous provider's key before switching
                SettingsManager.shared.setAPIKey(providerKeyText.isEmpty ? nil : providerKeyText, for: oldValue)
                providerKeyText = SettingsManager.shared.apiKey(for: newValue) ?? ""
            }

            if selectedProviderForKey.requiresAPIKey {
                RevealBlurTextField(placeholder: "API Key for \(selectedProviderForKey.displayName)", text: $providerKeyText)
                    .onChange(of: providerKeyText) { _, newValue in
                        SettingsManager.shared.setAPIKey(newValue.isEmpty ? nil : newValue, for: selectedProviderForKey)
                    }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text("Local — no API key required")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Panel Position Section

    private var panelPositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Panel Position")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Picker("Anchor", selection: $panelAnchor) {
                ForEach(PanelAnchor.allCases) { anchor in
                    Text(anchor.label).tag(anchor)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: panelAnchor) { _, newValue in
                SettingsManager.shared.panelAnchor = newValue
            }

            HStack(spacing: 12) {
                Stepper(value: $panelOffsetX, in: -400...400, step: 10) {
                    Text("X: \(Int(panelOffsetX))")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .onChange(of: panelOffsetX) { _, newValue in
                    SettingsManager.shared.panelOffsetX = newValue
                }

                Stepper(value: $panelOffsetY, in: -400...400, step: 10) {
                    Text("Y: \(Int(panelOffsetY))")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .onChange(of: panelOffsetY) { _, newValue in
                    SettingsManager.shared.panelOffsetY = newValue
                }
            }

            Button("Preview Position") {
                NotificationCenter.default.post(name: .geminiPreviewPosition, object: nil)
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Ollama Section

    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ollama")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            HStack(spacing: 8) {
                TextField("Base URL", text: $ollamaURL)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12, style: .continuous))
                    .onChange(of: ollamaURL) { _, newValue in
                        SettingsManager.shared.ollamaBaseURL = newValue
                    }

                Button(action: testOllamaConnection) {
                    if ollamaTesting {
                        SpinnerView()
                    } else {
                        Text("Test")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(ollamaTesting)
            }

            if let result = ollamaTestResult {
                Text(result)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(result.hasPrefix("✓") ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }

    private func testOllamaConnection() {
        ollamaTesting = true
        ollamaTestResult = nil
        Task {
            let models = await OllamaProvider.listInstalledModels()
            await MainActor.run {
                ollamaTesting = false
                if models.isEmpty {
                    ollamaTestResult = "✗ No response from \(ollamaURL). Is Ollama running?"
                } else {
                    ollamaTestResult = "✓ Found \(models.count) model(s): \(models.prefix(3).joined(separator: ", "))"
                }
            }
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Instructions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            GlassTextEditor(
                placeholder: "Instructions fed to every request…",
                text: $customInstructions,
                height: 72
            )
            .onChange(of: customInstructions) { _, newValue in
                SettingsManager.shared.customInstructions = newValue
            }
        }
    }

    // MARK: - Toggles Section

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Features")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            Toggle("Enable tool calling", isOn: $toolCalling)
                .toggleStyle(.switch)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .onChange(of: toolCalling) { _, newValue in
                    SettingsManager.shared.toolCallingEnabled = newValue
                }

            Toggle("Allow terminal commands", isOn: $runTerminal)
                .toggleStyle(.switch)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .onChange(of: runTerminal) { _, newValue in
                    SettingsManager.shared.runTerminalCommandsEnabled = newValue
                }
        }
    }

    // MARK: - Working Directory Section

    private var workingDirSection: some View {
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
        .onChange(of: workingDir) { _, newValue in
            SettingsManager.shared.workingDirectory = newValue
        }
    }

    // MARK: - Accessibility Section

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))

            HStack(spacing: 8) {
                Text("Option + G")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Capture selected text from any app")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("Requires Accessibility permission in System Settings.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Close Button

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

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Working Directory"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            workingDir = url.path
            SettingsManager.shared.workingDirectory = url.path
        }
    }
}
