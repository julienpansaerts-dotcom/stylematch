import SwiftUI

/// Carte principale de la pile : photos, taille, descriptif, nombre de paniers.
///
/// - Tap sur le tiers gauche / droit de la photo : photo précédente / suivante.
/// - Tap au centre ou sur les infos : ouvre la fiche détaillée.
struct GarmentCardView: View {
    let garment: Garment
    var dragOffset: CGSize = .zero
    var onOpenDetail: () -> Void = {}

    @State private var photoIndex = 0
    private let cornerRadius: CGFloat = 26

    var body: some View {
        ZStack(alignment: .bottom) {
            PhotoView(source: currentPhoto)
                .id(photoIndex)

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            tapZones

            info
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenDetail)
        }
        .overlay(alignment: .top) { topOverlay }
        .overlay { stamps }
        .overlay {
            if garment.status == .sold { soldOverlay }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if garment.isHot && garment.isAvailable {
                FlameBorder(cornerRadius: cornerRadius)
            }
        }
        .shadow(
            color: garment.isHot ? .orange.opacity(0.45) : .black.opacity(0.18),
            radius: garment.isHot ? 18 : 10,
            y: 6
        )
        .onChange(of: garment.id) { _, _ in photoIndex = 0 }
    }

    private var currentPhoto: PhotoSource? {
        garment.photos.indices.contains(photoIndex) ? garment.photos[photoIndex] : garment.photos.first
    }

    private func showPhoto(_ index: Int) {
        guard garment.photos.indices.contains(index) else {
            Haptics.impact(.soft)
            return
        }
        photoIndex = index
        Haptics.impact(.light)
    }

    // MARK: - Zones de tap (comme Tinder)

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showPhoto(photoIndex - 1) }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenDetail)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showPhoto(photoIndex + 1) }
        }
    }

    // MARK: - Haut de carte

    private var topOverlay: some View {
        VStack(spacing: 10) {
            if garment.photos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(garment.photos.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == photoIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(height: 4)
                    }
                }
            }
            HStack {
                Spacer()
                if garment.isHot {
                    HotBadge()
                }
            }
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    // MARK: - Informations

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(garment.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(garment.formattedPrice)
                    .font(.title2.weight(.heavy))
            }

            HStack(spacing: 6) {
                InfoChip(text: garment.sizeLabel, systemImage: "ruler")
                InfoChip(text: garment.brand, systemImage: "tag")
                InfoChip(text: garment.condition.shortLabel, systemImage: "sparkles")
            }

            Text(garment.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: garment.isHot ? "flame.fill" : "bag.fill")
                Text(garment.cartCountLabel)
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "info.circle")
                    .font(.body)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(garment.isHot ? Color.orange : Color.white.opacity(0.85))
            .animation(.snappy, value: garment.cartCount)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(18)
    }

    // MARK: - Tampons de swipe

    private var horizontalDominant: Bool {
        abs(dragOffset.width) >= abs(dragOffset.height)
    }

    private var rightProgress: Double {
        horizontalDominant ? max(0, min(1, dragOffset.width / 100)) : 0
    }

    private var leftProgress: Double {
        horizontalDominant ? max(0, min(1, -dragOffset.width / 100)) : 0
    }

    private var upProgress: Double {
        horizontalDominant ? 0 : max(0, min(1, -dragOffset.height / 110))
    }

    private var stamps: some View {
        ZStack {
            SwipeStamp(text: "PANIER", color: Theme.like, angle: -14)
                .opacity(rightProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 54)
                .padding(.leading, 24)
            SwipeStamp(text: "PASSER", color: Theme.pass, angle: 14)
                .opacity(leftProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 54)
                .padding(.trailing, 24)
            SwipeStamp(text: "ACHAT", color: Theme.buy)
                .opacity(upProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 190)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Vendu

    private var soldOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 10) {
                SwipeStamp(text: "VENDU", color: Theme.pass, angle: -10)
                Text("Trop tard, quelqu'un vient de l'acheter !")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Swipe pour continuer")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .allowsHitTesting(false)
    }
}
