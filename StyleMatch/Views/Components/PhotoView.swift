import SwiftUI

/// Affiche une photo de vêtement en remplissant tout l'espace disponible.
struct PhotoView: View {
    let source: PhotoSource?
    /// Version miniature (sans légende).
    var compact = false

    var body: some View {
        Color.clear
            .overlay {
                if let source {
                    content(for: source)
                } else {
                    PlaceholderPhoto(symbol: "photo", tint: .grey, caption: nil, variant: 0)
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func content(for source: PhotoSource) -> some View {
        switch source {
        case .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    PlaceholderPhoto(symbol: "photo", tint: .grey, caption: nil, variant: 0)
                default:
                    ZStack {
                        Color(.secondarySystemBackground)
                        ProgressView()
                    }
                }
            }
        case let .placeholder(symbol, tint, caption, variant):
            PlaceholderPhoto(symbol: symbol, tint: tint, caption: compact ? nil : caption, variant: variant)
        }
    }
}

/// Visuel de démonstration : dégradé de la couleur du vêtement + pictogramme.
/// Chaque « variante » imite un angle de prise de vue différent.
struct PlaceholderPhoto: View {
    let symbol: String
    let tint: GarmentColor
    let caption: String?
    let variant: Int

    var body: some View {
        ZStack {
            LinearGradient(colors: tint.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            GeometryReader { geo in
                Image(systemName: variant == 3 ? "tag.fill" : symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * symbolScale)
                    .foregroundStyle(tint.isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.92))
                    .rotation3DEffect(.degrees(variant == 1 ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .rotationEffect(.degrees(variant == 2 ? -18 : 0))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }

            if let caption {
                VStack {
                    HStack {
                        Text(caption.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 34)
                .padding(.leading, 14)
            }
        }
    }

    private var symbolScale: CGFloat {
        switch variant {
        case 2: return 0.85
        case 3: return 0.35
        default: return 0.55
        }
    }
}
