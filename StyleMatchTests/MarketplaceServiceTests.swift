import Foundation
import Testing
@testable import StyleMatch

@Suite("Service simulé")
struct MarketplaceServiceTests {

    @Test("Une pièce unique ne peut être vendue qu'une seule fois")
    func uniquePieceSoldOnce() async throws {
        let service = MockMarketplaceService.instant()
        let id = try #require(try await service.feed(filters: FeedFilters(), excluding: [], limit: 1).first?.id)

        async let first = service.purchase([id], details: .sample)
        async let second = service.purchase([id], details: .sample)
        let results = try await [first, second]

        #expect(results.filter { $0.order != nil }.count == 1)
        #expect(results.filter { $0.unavailable.map(\.id) == [id] }.count == 1)
    }

    @Test("L'achat du panier exclut les pièces déjà vendues sans les facturer")
    func partialPurchase() async throws {
        let service = MockMarketplaceService.instant()
        let items = try await service.feed(filters: FeedFilters(), excluding: [], limit: 2)
        let (kept, lost) = (items[0], items[1])
        await service.simulateExternalPurchase(of: lost.id)

        let result = try await service.purchase([kept.id, lost.id], details: .sample)
        let order = try #require(result.order)

        #expect(order.items.map(\.id) == [kept.id])
        #expect(order.subtotalCents == kept.priceCents)
        #expect(result.unavailable.map(\.id) == [lost.id])
    }

    @Test("Le devis serveur correspond exactement au montant facturé")
    func quoteMatchesOrder() async throws {
        let service = MockMarketplaceService.instant()
        let ids = try await service.feed(filters: FeedFilters(), excluding: [], limit: 3).map(\.id)

        let quote = try await service.quote(ids)
        let order = try #require(try await service.purchase(ids, details: .sample).order)

        #expect(quote.total(for: CheckoutDetails.sample.deliveryMethod) == order.totalCents)
        #expect(quote.unavailableIDs.isEmpty)
    }

    @Test("Le devis signale les pièces vendues")
    func quoteFlagsSoldItems() async throws {
        let service = MockMarketplaceService.instant()
        let ids = try await service.feed(filters: FeedFilters(), excluding: [], limit: 2).map(\.id)
        await service.simulateExternalPurchase(of: ids[1])

        let quote = try await service.quote(ids)
        #expect(quote.unavailableIDs == [ids[1]])
    }

    @Test("Ajouter puis retirer du panier rétablit le compteur")
    func cartCountRoundTrip() async throws {
        let service = MockMarketplaceService.instant()
        let garment = try #require(try await service.feed(filters: FeedFilters(), excluding: [], limit: 1).first)

        let added = try await service.addToCart(garment.id)
        #expect(added.cartCount == garment.cartCount + 1)
        try await service.removeFromCart(garment.id)

        let after = try #require(try await service.garments(ids: [garment.id]).first)
        #expect(after.cartCount == garment.cartCount)
    }
}
