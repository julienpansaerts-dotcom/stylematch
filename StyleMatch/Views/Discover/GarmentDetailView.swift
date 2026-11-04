import SwiftUI

/// Fiche détaillée d'un vêtement : toutes les photos + toutes les infos.
struct GarmentDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let garment: Garment
    /// Si fourni, affiche les boutons Passer / Acheter / Panier (ouvert depuis la pile).
    var onAction: ((SwipeDirection) -> Void)?

    @State private var photoIndex = 0

    private var live: Garment { store.liveVersion(of: garment) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    carousel
                    thumbnails
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        demandBanner
                        attributes
                        section("Description", text: live.details)
                        if let measurements = live.measurements {
                            section("Mesures", text: measurements)
                        }
                        uniqueNotice
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, onAction == nil ? 30 : 120)
            }
            .ignoresSafeArea(edges: .top)

            if onAction != nil && live.isAvailable {
                actionBar
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
    }

    // MARK: - Photos

    private var carousel: some View {
        ZStack(alignment: .top) {
            PhotoView(source: live.photos.indices.contains(photoIndex) ? live.photos[photoIndex] : live.photos.first)
                .frame(height: 500)
                .overlay {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { select(photoIndex - 1) }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { select(photoIndex + 1) }
                    }
                }

            if live.photos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(live.photos.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == photoIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)
                .allowsHitTesting(false)
            }
        }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(live.photos.indices, id: \.self) { index in
                    PhotoView(source: live.photos[index], compact: true)
                        .frame(width: 64, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(index == photoIndex ? Theme.accent : Color.clear, lineWidth: 2.5)
                        )
                        .onTapGesture { select(index) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func select(_ index: Int) {
        guard live.photos.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { photoIndex = index }
        Haptics.impact(.light)
    }

    // MARK: - Infos

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(live.title)
                    .font(.title.weight(.bold))
                Spacer()
                Text(live.formattedPrice)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(Theme.accent)
            }
            Text("\(live.brand) · \(live.sizeLabel)")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !live.isAvailable {
                Label("Vendu", systemImage: "xmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.pass)
            }
        }
    }

    @ViewBuilder
    private var demandBanner: some View {
        if live.isHot {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(Theme.hotRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pièce HOT 🔥")
                        .font(.headline)
                    Text("\(live.cartCount) personnes l'ont dans leur panier. Pièce unique : premier arrivé, premier servi !")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hotYellow.opacity(0.25))
            .toonCard(cornerRadius: 16, outline: 2.5, shadowOffset: 4, shadowColor: Theme.hotRed)
        } else {
            Label(live.cartCountLabel, systemImage: "bag.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var attributes: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            attribute("Taille", live.size == SizeCatalog.oneSize ? "Unique" : live.size, "ruler")
            attribute("État", live.condition.label, "sparkles")
            attribute("Couleur", live.color.label, "paintpalette")
            attribute("Marque", live.brand, "tag")
            attribute("Genre", live.gender.label, "person")
            attribute("Catégorie", live.category.label, "square.grid.2x2")
        }
    }

    private func attribute(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var uniqueNotice: some View {
        Label("Chaque article est une pièce unique de seconde main. Dès qu'il est acheté, il disparaît du panier de tous les autres utilisateurs.", systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            CircleActionButton(systemImage: "xmark", color: Theme.pass, size: 54) {
                onAction?(.left)
            }
            .accessibilityLabel("Passer")

            Button {
                onAction?(.right)
            } label: {
                Label("Panier", systemImage: "bag.fill.badge.plus")
            }
            .buttonStyle(GradientButtonStyle(color: Theme.like))

            Button {
                onAction?(.up)
            } label: {
                Label("Acheter", systemImage: "bolt.fill")
            }
            .buttonStyle(GradientButtonStyle(color: Theme.buy))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
