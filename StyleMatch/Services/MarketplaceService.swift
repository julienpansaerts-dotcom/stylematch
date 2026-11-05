import Foundation

/// Événements poussés en temps réel par le serveur (WebSocket / Realtime).
enum MarketplaceEvent: Sendable {
    /// Une pièce unique vient d'être vendue. Elle doit disparaître de la pile
    /// et du panier de tous les autres utilisateurs.
    case garmentSold(id: String, title: String, byCurrentUser: Bool)
    /// Le nombre de paniers contenant la pièce a changé (indicateur HOT).
    case cartCountChanged(id: String, count: Int)
    /// Le statut de livraison d'une de mes commandes a changé.
    case orderUpdated(Order)
}

struct CheckoutDetails: Sendable {
    let buyerName: String
    let address: ShippingAddress
    let deliveryMethod: DeliveryMethod
    let relayPoint: String
    let payment: PaymentMethod
}

struct PurchaseResult: Sendable {
    /// Commande créée pour les pièces effectivement achetées (nil si aucune).
    let order: Order?
    /// Pièces vendues à quelqu'un d'autre avant la validation du paiement.
    let unavailable: [Garment]
}

enum MarketplaceError: LocalizedError {
    case notFound
    case alreadySold
    case paymentDeclined
    case network

    var errorDescription: String? {
        switch self {
        case .notFound: return "Ce vêtement n'existe plus."
        case .alreadySold: return "Trop tard, cette pièce unique vient d'être vendue."
        case .paymentDeclined: return "Le paiement a été refusé."
        case .network: return "Connexion impossible. Vérifie ton réseau."
        }
    }
}

/// Contrat entre l'application et le backend.
///
/// `MockMarketplaceService` l'implémente en mémoire (mode démo). Pour passer en
/// production, il suffit d'écrire une implémentation qui parle au vrai backend
/// (voir `backend/supabase/schema.sql` et `docs/ARCHITECTURE.md`).
protocol MarketplaceService: Sendable {
    /// Pièces disponibles correspondant aux filtres, hors `excluding`.
    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment]
    func garments(ids: [String]) async throws -> [Garment]

    func cart() async throws -> [Garment]
    func addToCart(_ garmentID: String) async throws -> Garment
    func removeFromCart(_ garmentID: String) async throws

    /// Devis (frais de livraison, protection acheteur, total) calculé par le serveur.
    func quote(_ garmentIDs: [String]) async throws -> PriceQuote

    /// Achat atomique : chaque pièce n'est vendue qu'une seule fois.
    func purchase(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PurchaseResult
    func orders() async throws -> [Order]

    /// Flux d'événements temps réel.
    func events() async -> AsyncStream<MarketplaceEvent>
}
