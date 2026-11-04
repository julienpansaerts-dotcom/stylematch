import Foundation

enum Money {
    static func format(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }
}

/// Règles de prix partagées entre l'écran de paiement et le service.
/// (En production, le serveur recalcule toujours le montant final.)
enum Pricing {
    static func shipping(for method: DeliveryMethod) -> Int {
        switch method {
        case .home: return 490
        case .relayPoint: return 290
        }
    }

    /// Protection acheteur : 0,70 € + 5 % du sous-total.
    static func serviceFee(subtotal: Int) -> Int {
        subtotal == 0 ? 0 : 70 + subtotal * 5 / 100
    }

    static func total(subtotal: Int, method: DeliveryMethod) -> Int {
        guard subtotal > 0 else { return 0 }
        return subtotal + shipping(for: method) + serviceFee(subtotal: subtotal)
    }
}
