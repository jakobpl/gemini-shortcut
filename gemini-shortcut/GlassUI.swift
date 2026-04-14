import SwiftUI

// MARK: - Visual Effect

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.masksToBounds = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Liquid Glass Container

struct LiquidGlassContainer: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .opacity(0.55)
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.35)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Liquid Glow Overlay

struct LiquidGlowOverlay: View {
    let cornerRadius: CGFloat
    @State private var rotation: Double = 0
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.0)
                    ]),
                    center: .center,
                    angle: .degrees(rotation)
                ),
                lineWidth: 1.5
            )
            .onAppear {
                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Liquid Orb (Thinking Indicator)

struct LiquidOrb: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .blur(radius: 10)
            
            Circle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: 30, height: 30)
                .scaleEffect(isPulsing ? 1.25 : 1.0)
                .blur(radius: 5)
            
            Circle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 16, height: 16)
            
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
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
                    .foregroundStyle(Color.white.opacity(0.45))
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .blur(radius: (isFocused || isHovered) ? 0 : 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Glass Text Field

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if isSecure {
                SecureField("", text: $text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white)
            } else {
                TextField("", text: $text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Glass Text Editor

struct GlassTextEditor: View {
    @Binding var text: String
    let height: CGFloat
    
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Color.white)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - Glass Pill Button

struct GlassPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.3 : 0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Toggle

struct GlassToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            Button(action: { isOn.toggle() }) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isOn ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.12))
                        .frame(width: 50, height: 28)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isOn ? 0.35 : 0.22), lineWidth: 1)
                        )
                    
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: isOn ? 32 : 22, height: isOn ? 32 : 22)
                        .blur(radius: 5)
                        .offset(x: isOn ? 20 : 3)
                        .opacity(isOn ? 1 : 0.6)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color.white, Color.white.opacity(0.75)]),
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 14
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 0.5)
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: isOn ? 25 : 3)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
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
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.35) : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isDisabled ? Color.white.opacity(0.06) : Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isDisabled ? 0.08 : 0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "g.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
