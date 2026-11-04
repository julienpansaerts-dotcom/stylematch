import Foundation
@testable import StyleMatch

extension LocalPersistence {
    /// Stockage isolé et jetable pour chaque test.
    static func ephemeral() -> LocalPersistence {
        let suite = "stylematch.tests.\(UUID().uuidString)"
        return LocalPersistence(
            defaults: UserDefaults(suiteName: suite) ?? .standard,
            keychainService: suite
        )
    }
}

extension MockMarketplaceService {
    /// Service simulé instantané et sans autres acheteurs.
    static func instant() -> MockMarketplaceService {
        MockMarketplaceService(simulateOtherUsers: false, latency: 0...0, paymentDelay: 0)
    }
}

extension CheckoutDetails {
    static let sample = CheckoutDetails(
        buyerName: "Test Testeur",
        address: ShippingAddress(line1: "1 rue du Test", postalCode: "75001", city: "Paris"),
        deliveryMethod: .home,
        relayPoint: "",
        payment: PaymentMethod(kind: .applePay)
    )
}

/// Enveloppe un service et ajoute des délais réseau précis pour reproduire
/// les situations de concurrence (réponses qui arrivent dans le désordre).
actor DelayedService: MarketplaceService {
    private let base: MockMarketplaceService
    private let addDelay: Int
    private let removeDelay: Int
    private let feedDelays: [Int]
    private var feedCalls = 0

    /// - Parameter feedDelays: délai (ms) du 1er, 2e, 3e… appel à `feed`.
    init(base: MockMarketplaceService, addDelay: Int = 0, removeDelay: Int = 0, feedDelays: [Int] = []) {
        self.base = base
        self.addDelay = addDelay
        self.removeDelay = removeDelay
        self.feedDelays = feedDelays
    }

    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment] {
        let index = feedCalls
        feedCalls += 1
        let delay = index < feedDelays.count ? feedDelays[index] : 0
        try await Task.sleep(for: .milliseconds(delay))
        return try await base.feed(filters: filters, excluding: excluding, limit: limit)
    }

    func garments(ids: [String]) async throws -> [Garment] { try await base.garments(ids: ids) }
    func cart() async throws -> [Garment] { try await base.cart() }

    func addToCart(_ garmentID: String) async throws -> Garment {
        try await Task.sleep(for: .milliseconds(addDelay))
        return try await base.addToCart(garmentID)
    }

    func removeFromCart(_ garmentID: String) async throws {
        try await Task.sleep(for: .milliseconds(removeDelay))
        try await base.removeFromCart(garmentID)
    }

    func quote(_ garmentIDs: [String]) async throws -> PriceQuote { try await base.quote(garmentIDs) }

    func purchase(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PurchaseResult {
        try await base.purchase(garmentIDs, details: details)
    }

    func orders() async throws -> [Order] { try await base.orders() }
    func events() async -> AsyncStream<MarketplaceEvent> { await base.events() }
}
