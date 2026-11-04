import SwiftUI

/// Bouton rond de la barre d'actions (passer / acheter / panier).
struct CircleActionButton: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 60
    var label: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
                    )
                    .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 1))
                if let label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label ?? "")
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Gros bouton principal au dégradé de la marque.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.brandGradient)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
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
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
