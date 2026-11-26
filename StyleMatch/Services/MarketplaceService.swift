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
    /// Moyen de paiement du mode démo. `nil` avec Stripe (saisi dans la feuille Stripe).
    let payment: PaymentMethod?
}

struct PurchaseResult: Sendable {
    /// Commande créée pour les pièces effectivement achetées (nil si aucune).
    let order: Order?
    /// Pièces vendues à quelqu'un d'autre avant la validation du paiement.
    let unavailable: [Garment]
}

/// Paiement préparé : pièces réservées et montant exact.
struct PaymentPreparation: Sendable {
    let paymentIntentID: String?
    /// Secret à passer à la feuille de paiement Stripe. `nil` = pas de feuille (mode démo).
    let clientSecret: String?
    let reservedIDs: [String]
    let unavailable: [Garment]
    let totalCents: Int
}

/// Historique des swipes de l'utilisateur (synchronisé entre ses appareils).
struct SwipeHistory: Sendable {
    var passed: [String] = []
    var liked: Set<String> = []
}

/// Fiche d'une pièce en cours de création / modification par la boutique.
struct GarmentDraft: Sendable {
    var id: String?
    var title = ""
    var brand = ""
    var summary = ""
    var details = ""
    var measurements = ""
    var size = "M"
    var gender: Gender = .unisex
    var category: GarmentCategory = .tshirts
    var condition: GarmentCondition = .veryGood
    var color: GarmentColor = .black
    var priceEuros = ""
    /// Photos déjà en ligne (conservées dans l'ordre).
    var existingPhotos: [URL] = []
    /// Nouvelles photos (JPEG) à envoyer.
    var newPhotos: [Data] = []

    var priceCents: Int? {
        let normalized = priceEuros.replacingOccurrences(of: ",", with: ".").trimmed
        guard let value = Double(normalized), value > 0, value < 100_000 else { return nil }
        return Int((value * 100).rounded())
    }

    var photoCount: Int { existingPhotos.count + newPhotos.count }

    var isValid: Bool {
        !title.trimmed.isEmpty && priceCents != nil && photoCount > 0
    }

    init() {}

    init(garment: Garment) {
        id = garment.id
        title = garment.title
        brand = garment.brand
        summary = garment.summary
        details = garment.details
        measurements = garment.measurements ?? ""
        size = garment.size
        gender = garment.gender
        category = garment.category
        condition = garment.condition
        color = garment.color
        priceEuros = String(format: "%.2f", Double(garment.priceCents) / 100).replacingOccurrences(of: ".", with: ",")
        existingPhotos = garment.photos.compactMap {
            if case .remote(let url) = $0 { return url }
            return nil
        }
    }
}

enum MarketplaceError: LocalizedError, Equatable {
    case notFound
    case alreadySold
    case paymentDeclined
    case network
    case notSignedIn
    case notAllowed
    /// Paiement reçu mais commande pas encore confirmée par le serveur.
    case paymentPending
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Ce vêtement n'existe plus."
        case .alreadySold: return "Trop tard, cette pièce unique vient d'être vendue."
        case .paymentDeclined: return "Le paiement a été refusé."
        case .network: return "Connexion impossible. Vérifie ton réseau."
        case .notSignedIn: return "Connecte-toi pour continuer."
        case .notAllowed: return "Action réservée à la boutique."
        case .paymentPending:
            return "Paiement reçu ! Ta commande apparaîtra dans « Mes commandes » dans quelques instants."
        case .server(let message): return message
        }
    }
}

/// Contrat entre l'application et le backend.
///
/// - `MockMarketplaceService` : mode démo, en mémoire.
/// - `SupabaseMarketplaceService` : vrai serveur (Supabase + Stripe).
protocol MarketplaceService: Sendable {
    /// `true` si le paiement passe par la feuille Stripe (sinon : paiement simulé).
    var usesExternalPaymentSheet: Bool { get }

    // MARK: Catalogue & swipe
    /// Pièces disponibles correspondant aux filtres, hors `excluding`.
    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment]
    func garments(ids: [String]) async throws -> [Garment]
    func swipeHistory() async throws -> SwipeHistory
    func recordSwipe(_ garmentID: String, direction: SwipeDirection) async throws
    /// Oublie des swipes (annulation, « revoir les passés »).
    func forgetSwipes(_ garmentIDs: [String]) async throws

    // MARK: Panier
    func cart() async throws -> [Garment]
    func addToCart(_ garmentID: String) async throws -> Garment
    func removeFromCart(_ garmentID: String) async throws

    // MARK: Paiement
    /// Devis (frais de livraison, protection acheteur, total) calculé par le serveur.
    func quote(_ garmentIDs: [String]) async throws -> PriceQuote
    /// Réserve les pièces et prépare le paiement du montant exact.
    func preparePayment(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PaymentPreparation
    /// Après paiement : attend la commande créée par le serveur.
    func completePayment(_ preparation: PaymentPreparation, details: CheckoutDetails) async throws -> PurchaseResult
    /// Paiement abandonné : libère les pièces réservées.
    func cancelPayment(_ preparation: PaymentPreparation) async

    // MARK: Compte
    func orders() async throws -> [Order]
    func loadProfile() async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) async throws

    /// Flux d'événements temps réel.
    func events() async -> AsyncStream<MarketplaceEvent>

    // MARK: Boutique (administration)
    func adminCatalogue() async throws -> [Garment]
    func saveGarment(_ draft: GarmentDraft) async throws -> Garment
    func setGarmentWithdrawn(_ garmentID: String, withdrawn: Bool) async throws
    func adminOrders() async throws -> [Order]
    func updateOrder(_ orderID: String, status: OrderStatus, trackingNumber: String?) async throws -> Order
}
