import Foundation

/// Règles de prix du SERVEUR simulé.
///
/// Elles ne sont utilisées que par `MockMarketplaceService` ; l'app obtient les
/// montants via `MarketplaceService.quote(_:)`. En production, ces règles vivent
/// uniquement dans la base (`shipping_cents` / `service_fee_cents` dans
/// `backend/supabase/schema.sql`).
enum ServerPricing {
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

    static func quote(for garments: [Garment], requestedIDs: [String]) -> PriceQuote {
        let available = garments.filter(\.isAvailable)
        let subtotal = available.reduce(0) { $0 + $1.priceCents }
        return PriceQuote(
            subtotalCents: subtotal,
            shippingCents: Dictionary(uniqueKeysWithValues: DeliveryMethod.allCases.map { ($0, shipping(for: $0)) }),
            serviceFeeCents: serviceFee(subtotal: subtotal),
            unavailableIDs: Set(requestedIDs).subtracting(available.map(\.id))
        )
    }
}
