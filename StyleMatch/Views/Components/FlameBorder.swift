import SwiftUI

/// Encadrement de flammes animé autour d'une pièce HOT.
struct FlameBorder: View {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 4
    var showsFlames = true

    private let colors: [Color] = [
        .red, .orange, .yellow, .orange, .red, Color(red: 1, green: 0.2, blue: 0.4), .red
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 90).truncatingRemainder(dividingBy: 360))
            let flicker = 0.75 + 0.25 * sin(t * 9)
            let gradient = AngularGradient(colors: colors, center: .center, angle: angle)
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                // Halo lumineux
                shape
                    .strokeBorder(gradient, lineWidth: lineWidth * 3)
                    .blur(radius: 10)
                    .opacity(0.85 * flicker)
                // Bordure nette
                shape
                    .strokeBorder(gradient, lineWidth: lineWidth)
                if showsFlames {
                    flames(time: t)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Petites flammes qui dansent sur le contour de la carte.
    private func flames(time t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let spots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
                (0.12, 0, 22), (0.32, 0, 26), (0.5, 0, 30), (0.68, 0, 26), (0.88, 0, 22),
                (0, 0.22, 20), (0, 0.48, 18), (1, 0.22, 20), (1, 0.48, 18)
            ]
            ForEach(spots.indices, id: \.self) { index in
                let spot = spots[index]
                let scale = 0.8 + 0.3 * sin(t * 7 + Double(index) * 1.3)
                Image(systemName: "flame.fill")
                    .font(.system(size: spot.size))
                    .foregroundStyle(Theme.flameGradient)
                    .shadow(color: .orange.opacity(0.9), radius: 6)
                    .scaleEffect(scale, anchor: .bottom)
                    .position(x: w * spot.x, y: h * spot.y - spot.size * 0.3)
            }
        }
    }
}
