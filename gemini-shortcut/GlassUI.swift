import SwiftUI

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Liquid Glass Container
// Uses macOS 26 native .glassEffect() for real chromatic, refractive glass.
// Place this as a background layer behind content inside a ZStack.

struct LiquidGlassContainer: View {
    var cornerRadius: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Liquid Orb (Thinking Indicator)

struct LiquidOrb: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 50, height: 50)
                .scaleEffect(isPulsing ? 1.35 : 1.0)
                .blur(radius: 12)

            Circle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .blur(radius: 5)

            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.95), Color.accentColor.opacity(0.7)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 12
                ))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.75))
                .shadow(color: Color.accentColor.opacity(0.5), radius: isPulsing ? 8 : 4, x: 0, y: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Reveal Blur Text Field
// Placeholder-as-label: blurs content when not focused/hovered so key is hidden at a glance.

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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.45 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Glass Text Field

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white)
                .textFieldStyle(.plain)
                .focused($isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.45 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.45 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Glass Pill Button (model selector)

struct GlassPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.65))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(isHovered && !isSelected ? 0.85 : 1.0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.5 : 0.15), lineWidth: 1.0)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Glass Toggle

struct GlassToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                    isOn.toggle()
                }
            }) {
                ZStack(alignment: .leading) {
                    // Track — glass base with accent tint overlay when on
                    ZStack {
                        Capsule()
                            .glassEffect(in: Capsule())
                            .frame(width: 48, height: 26)
                        if isOn {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.28))
                                .frame(width: 48, height: 26)
                        }
                    }
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(isOn ? 0.45 : 0.20), lineWidth: 1)
                    )

                    // Glow halo behind thumb
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: isOn ? 28 : 20, height: isOn ? 28 : 20)
                        .blur(radius: 5)
                        .offset(x: isOn ? 21 : 3)

                    // Glass bead thumb
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.white, Color.white.opacity(0.72)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 13
                        ))
                        .frame(width: 21, height: 21)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 0.6))
                        .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                        .shadow(color: Color.accentColor.opacity(isOn ? 0.35 : 0), radius: 5, x: 0, y: 0)
                        .offset(x: isOn ? 24 : 3)
                }
                .frame(width: 48, height: 26)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.3) : Color.white.opacity(isHovered ? 1.0 : 0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .opacity(isDisabled ? 0.5 : (isHovered ? 1.0 : 0.85))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
