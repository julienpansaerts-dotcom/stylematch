import SwiftUI

// Style « cel-shading » (dessin animé / jeu vidéo) : contours épais foncés,
// aplats de couleurs francs et ombres dures sans flou. Tout est statique :
// rien ne tourne en continu, donc aucun coût batterie.

extension Theme {
    /// Couleur d'encre des contours et des ombres dures.
    static let ink = Color(red: 0.10, green: 0.07, blue: 0.16)
    static let hotOrange = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let hotYellow = Color(red: 1.0, green: 0.86, blue: 0.24)
    static let hotRed = Color(red: 0.90, green: 0.20, blue: 0.16)
}

/// Encadré d'une pièce HOT : bandes d'aplats orange / jaune cernées d'encre.
struct HotFrame: View {
    var cornerRadius: CGFloat
    /// 1 pour une carte, plus petit pour une vignette.
    var scale: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            // Contour d'encre extérieur
            shape.strokeBorder(Theme.ink, lineWidth: 12 * scale)
            // Bande orange principale
            shape.inset(by: 3 * scale).strokeBorder(Theme.hotOrange, lineWidth: 6 * scale)
            // Reflet jaune (la « lumière » du cel-shading)
            shape.inset(by: 3 * scale).strokeBorder(Theme.hotYellow, lineWidth: 2.5 * scale)
            // Fin trait d'encre intérieur
            shape.inset(by: 9 * scale).strokeBorder(Theme.ink, lineWidth: 2 * scale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Contour d'encre + ombre dure décalée, façon dessin animé.
    func toonCard(cornerRadius: CGFloat, outline: CGFloat = 3, shadowOffset: CGFloat = 6, shadowColor: Color = Theme.ink) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: outline))
            .background(shape.fill(shadowColor).offset(x: shadowOffset * 0.6, y: shadowOffset))
    }
}
