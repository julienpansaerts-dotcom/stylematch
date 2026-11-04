import Foundation

enum Money {
    static func format(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }
}

/// Devis calculé par le serveur pour un ensemble de pièces.
///
/// L'app n'a aucune règle de prix codée en dur : elle affiche exactement ce que
/// le serveur facturera (frais de livraison, protection acheteur, total).
struct PriceQuote: Equatable, Sendable {
    /// Somme des pièces encore disponibles.
    let subtotalCents: Int
    /// Frais de livraison proposés pour chaque mode.
    let shippingCents: [DeliveryMethod: Int]
    let serviceFeeCents: Int
    /// Pièces demandées qui ne sont plus disponibles (exclues du devis).
    let unavailableIDs: Set<String>

    func shipping(for method: DeliveryMethod) -> Int {
        subtotalCents > 0 ? (shippingCents[method] ?? 0) : 0
    }

    func total(for method: DeliveryMethod) -> Int {
        subtotalCents > 0 ? subtotalCents + shipping(for: method) + serviceFeeCents : 0
    }
}
