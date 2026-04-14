import SwiftUI

struct SettingsView: View {
    @State private var apiKey = SettingsManager.shared.apiKey ?? ""
    @State private var customInstructions = SettingsManager.shared.customInstructions
    @State private var selectedModel = SettingsManager.shared.selectedModel
    @State private var toolCalling = SettingsManager.shared.toolCallingEnabled
    @State private var runTerminal = SettingsManager.shared.runTerminalCommandsEnabled
    @State private var appeared = false
    @State private var isHovering = false

    let dismiss: () -> Void
    let models = ["gemini-3.1-pro-preview", "gemini-3.1-flash-lite-preview"]

    var body: some View {
        ZStack {
            LiquidGlassContainer(cornerRadius: 24)

            VStack(spacing: 12) {
                // API Key — placeholder acts as label, blurs when unfocused
                RevealBlurTextField(placeholder: "API Key  (AIza… or \"dev\" to test)", text: $apiKey)

                // Model picker
                modelPicker

                // Custom instructions — placeholder as label
                GlassTextEditor(
                    placeholder: "Custom instructions…",
                    text: $customInstructions,
                    height: 72
                )

                // Toggles
                VStack(spacing: 8) {
                    GlassToggle(title: "Enable tool calling", isOn: $toolCalling)
                    GlassToggle(title: "Allow terminal commands", isOn: $runTerminal)
                }

                // Save
                GlassButton(
                    title: "Save",
                    action: saveAndDismiss,
                    isDisabled: apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            // Flow-in on open
            .offset(y: appeared ? 0 : 18)
            .opacity(appeared ? 1 : 0)

            // Close button on hover
            closeButton
        }
        .frame(width: 360, height: 380)
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

    // MARK: - Close button

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: dismiss) {
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

    // MARK: - Model Picker

    private var modelPicker: some View {
        HStack(spacing: 6) {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(models, id: \.self) { model in
                        GlassPillButton(
                            title: modelLabel(for: model),
                            isSelected: selectedModel == model,
                            action: { selectedModel = model }
                        )
                    }
                }
            }
            Spacer()
        }
    }

    private func modelLabel(for model: String) -> String {
        if model.contains("flash") { return "Flash Lite" }
        if model.contains("pro")   { return "Pro" }
        return model
    }

    private func saveAndDismiss() {
        SettingsManager.shared.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsManager.shared.customInstructions = customInstructions
        SettingsManager.shared.selectedModel = selectedModel
        SettingsManager.shared.toolCallingEnabled = toolCalling
        SettingsManager.shared.runTerminalCommandsEnabled = runTerminal
        dismiss()
    }
}
