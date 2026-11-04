import SwiftUI

/// Bouton rond de la barre d'actions (passer / acheter / panier), style cel-shading :
/// contour d'encre, aplat de couleur et ombre dure qui « s'enfonce » à l'appui.
struct CircleActionButton: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 60
    var label: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .buttonStyle(ToonCircleButtonStyle(color: color))
        .overlay(alignment: .bottom) {
            if let label {
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
        }
        .padding(.bottom, label == nil ? 0 : 18)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label ?? "")
    }
}

/// Bouton rond cel-shading qui s'enfonce dans son ombre quand on appuie.
struct ToonCircleButtonStyle: ButtonStyle {
    let color: Color
    private let depth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(Circle().fill(color))
            .overlay(
                // Reflet plat en haut à gauche
                Circle()
                    .trim(from: 0.55, to: 0.8)
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(7)
            )
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
            .offset(y: pressed ? depth : 0)
            .background(Circle().fill(Theme.ink).offset(y: depth))
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Gros bouton principal : aplat de la couleur de la marque, contour d'encre,
/// ombre dure qui s'enfonce à l'appui.
struct GradientButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled
    private let depth: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(shape.fill(color))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 3))
            .offset(y: pressed ? depth : 0)
            .background(shape.fill(Theme.ink).offset(y: depth))
            .padding(.bottom, depth)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
    }
}

/// Puce sélectionnable utilisée dans les filtres.
struct SelectableChip: View {
    let title: String
    var systemImage: String?
    var swatch: Color?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                }
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)))
            )
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: isSelected ? 2.5 : 0))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
