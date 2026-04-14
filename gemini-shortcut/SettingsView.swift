import SwiftUI

struct SettingsView: View {
    @State private var apiKey = SettingsManager.shared.apiKey ?? ""
    @State private var customInstructions = SettingsManager.shared.customInstructions
    @State private var selectedModel = SettingsManager.shared.selectedModel
    @State private var toolCalling = SettingsManager.shared.toolCallingEnabled
    @State private var runTerminal = SettingsManager.shared.runTerminalCommandsEnabled
    @State private var showGoogleSoon = false
    
    let dismiss: () -> Void
    
    let models = ["gemini-3.1-pro-preview", "gemini-3.1-flash-lite-preview"]
    
    var body: some View {
        ZStack {
            LiquidGlassContainer(cornerRadius: 28)
            LiquidGlowOverlay(cornerRadius: 28)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    label("API Key")
                    RevealBlurTextField(placeholder: "AIza...", text: $apiKey)
                    
                    label("Default Model")
                    modelPicker
                    
                    label("Custom Instructions")
                    GlassTextEditor(text: $customInstructions, height: 64)
                    
                    label("Capabilities")
                    VStack(spacing: 10) {
                        GlassToggle(title: "Enable tool calling", isOn: $toolCalling)
                        GlassToggle(title: "Allow terminal commands", isOn: $runTerminal)
                    }
                }
                
                Spacer(minLength: 4)
                
                HStack(spacing: 12) {
                    GlassButton(
                        title: "Save",
                        action: saveAndDismiss,
                        isDisabled: apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                    GlassIconButton(action: { showGoogleSoon = true })
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(width: 380, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .alert("Coming Soon", isPresented: $showGoogleSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google Sign-In will be available in a future update.")
        }
    }
    
    private var modelPicker: some View {
        HStack(spacing: 8) {
            ForEach(models, id: \.self) { model in
                GlassPillButton(
                    title: model,
                    isSelected: selectedModel == model,
                    action: { selectedModel = model }
                )
            }
        }
    }
    
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.55))
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
