import SwiftUI

/// Bandeau de notification in-app (ex. « Trop tard, la pièce a été vendue »).
struct NoticeBanner: View {
    let notice: Notice
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.bold))
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(.horizontal, 12)
        .onTapGesture(perform: onDismiss)
    }

    private var icon: String {
        switch notice.kind {
        case .soldOut: return "heart.slash.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .soldOut: return Theme.pass
        case .success: return Theme.like
        case .info: return Theme.buy
        case .error: return .orange
        }
    }
}
