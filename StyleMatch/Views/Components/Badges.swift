import SwiftUI

/// Badge « HOT » affiché sur les pièces très demandées.
struct HotBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .symbolEffect(.pulse)
            Text("HOT")
                .fontWeight(.black)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .orange.opacity(0.6), radius: 6)
    }
}

/// Petite étiquette d'information sur la carte (taille, marque…).
struct InfoChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Tampon « PASSER / PANIER / ACHAT » qui apparaît pendant le swipe.
struct SwipeStamp: View {
    let text: String
    let color: Color
    var angle: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}

/// Pastille de statut de commande.
struct StatusPill: View {
    let order: Order

    var body: some View {
        Label(order.statusLabel, systemImage: order.status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch order.status {
        case .delivered: return Theme.like
        case .outForDelivery, .inTransit, .shipped: return Theme.buy
        case .confirmed, .preparing: return .orange
        }
    }
}

/// Pastille numérique posée sur un bouton.
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Theme.accent, in: Capsule())
        }
    }
}
