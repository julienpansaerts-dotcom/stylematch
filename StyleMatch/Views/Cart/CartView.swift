import SwiftUI

/// Panier dynamique : une pièce achetée par quelqu'un d'autre disparaît en direct.
struct CartView: View {
    @Environment(AppStore.self) private var store
    var onBrowse: () -> Void = {}

    @State private var detailGarment: Garment?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isSignedIn {
                    SignInPrompt(
                        title: "Ton panier",
                        message: "Connecte-toi pour garder tes coups de cœur et les acheter."
                    )
                } else if store.cart.isEmpty && store.lostItems.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Panier")
            .sheet(item: $detailGarment) { garment in
                GarmentDetailView(garment: garment)
            }
        }
    }

    // MARK: - Liste

    private var list: some View {
        List {
            if !store.cart.isEmpty {
                Section {
                    ForEach(store.cart) { garment in
                        CartRow(garment: garment) {
                            store.buy(garment)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { detailGarment = garment }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { store.removeFromCart(garment) }
                            } label: {
                                Label("Retirer", systemImage: "trash")
                            }
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                } header: {
                    Text(store.cart.count > 1 ? "\(store.cart.count) pièces uniques" : "1 pièce unique")
                } footer: {
                    Text("Chaque pièce est unique : si quelqu'un l'achète avant toi, elle disparaît automatiquement de ton panier.")
                }
            }

            if !store.lostItems.isEmpty {
                Section {
                    ForEach(store.lostItems) { garment in
                        LostItemRow(garment: garment)
                    }
                } header: {
                    HStack {
                        Text("Trop tard… vendues entre-temps")
                        Spacer()
                        Button("Effacer") {
                            withAnimation { store.clearLostItems() }
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: store.cart.map(\.id))
        .animation(.default, value: store.lostItems.map(\.id))
        .safeAreaInset(edge: .bottom) {
            if !store.cart.isEmpty {
                checkoutBar
            }
        }
    }

    private var checkoutBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Sous-total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(store.cartSubtotalCents))
                    .font(.headline)
                    .contentTransition(.numericText())
            }
            Button {
                store.buyWholeCart()
            } label: {
                Label(
                    store.cart.count > 1 ? "Tout acheter (\(store.cart.count) pièces)" : "Acheter",
                    systemImage: "bolt.fill"
                )
            }
            .buttonStyle(GradientButtonStyle())
            if store.cart.count > 1 {
                Text("📦 Une seule livraison pour tout le panier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ton panier est vide", systemImage: "bag")
        } description: {
            Text("Swipe à droite sur un vêtement pour l'ajouter ici.")
        } actions: {
            Button("Découvrir des pièces", action: onBrowse)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }
}

// MARK: - Lignes

struct CartRow: View {
    let garment: Garment
    let onBuy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(source: garment.photos.first, compact: true)
                .frame(width: 72, height: 90)
                .toonCard(cornerRadius: 12, outline: 2, shadowOffset: 3, shadowColor: garment.isHot ? Theme.hotRed : Theme.ink)
                .overlay {
                    if garment.isHot {
                        HotFrame(cornerRadius: 12, scale: 0.45)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(garment.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(garment.brand) · \(garment.sizeLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(garment.formattedPrice)
                    .font(.subheadline.weight(.bold))
                if garment.otherInterestedCount > 0 {
                    Label(
                        garment.otherInterestedCount > 1
                            ? "\(garment.otherInterestedCount) autres la veulent"
                            : "1 autre personne la veut",
                        systemImage: garment.isHot ? "flame.fill" : "person.2.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(garment.isHot ? Theme.hotOrange : Color.secondary)
                    .contentTransition(.numericText())
                }
            }

            Spacer(minLength: 4)

            Button("Acheter", action: onBuy)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

struct LostItemRow: View {
    let garment: Garment

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(source: garment.photos.first, compact: true)
                .frame(width: 56, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .grayscale(1)
                .overlay {
                    Text("VENDU")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Theme.pass, in: RoundedRectangle(cornerRadius: 4))
                        .rotationEffect(.degrees(-12))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(garment.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough()
                Text("Achetée par quelqu'un d'autre")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .opacity(0.7)
    }
}
