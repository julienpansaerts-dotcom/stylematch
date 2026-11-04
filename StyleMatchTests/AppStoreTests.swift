import Foundation
import Testing
@testable import StyleMatch

@MainActor
@Suite("AppStore")
struct AppStoreTests {

    // MARK: Bug 1 — annuler un swipe à droite

    @Test("Annuler un swipe à droite pendant l'envoi laisse le panier serveur vide")
    func undoWhileAddIsInFlight() async throws {
        let base = MockMarketplaceService.instant()
        // L'ajout est lent, le retrait instantané : sans mise en ordre,
        // le retrait arriverait avant l'ajout.
        let service = DelayedService(base: base, addDelay: 300, removeDelay: 0)
        let store = AppStore(service: service, persistence: .ephemeral())
        await store.reloadDeck()
        let garment = try #require(store.deck.first)
        let initialCount = garment.cartCount

        store.swipe(garment, .right)
        try await Task.sleep(for: .milliseconds(50)) // l'ajout est parti
        store.undoLastSwipe()
        await store.waitForPendingCartOperations()

        #expect(try await base.cart().isEmpty)
        let serverGarment = try #require(try await base.garments(ids: [garment.id]).first)
        #expect(serverGarment.cartCount == initialCount)
        #expect(store.cart.isEmpty)
        #expect(store.deck.first?.id == garment.id)
    }

    @Test("Annuler immédiatement un swipe à droite n'envoie rien au serveur")
    func undoBeforeAddIsSent() async throws {
        let base = MockMarketplaceService.instant()
        let store = AppStore(service: DelayedService(base: base, addDelay: 200), persistence: .ephemeral())
        await store.reloadDeck()
        let garment = try #require(store.deck.first)

        store.swipe(garment, .right)
        store.undoLastSwipe()
        await store.waitForPendingCartOperations()

        #expect(try await base.cart().isEmpty)
        let serverGarment = try #require(try await base.garments(ids: [garment.id]).first)
        #expect(serverGarment.cartCount == garment.cartCount)
    }

    // MARK: Bug 2 — filtres ignorés

    @Test("Un complément de pile lancé avant un changement de filtres est ignoré")
    func staleRefillIsDiscarded() async throws {
        let base = MockMarketplaceService.instant()
        // 1er appel : chargement initial · 2e : complément lent · 3e : nouveaux filtres.
        let service = DelayedService(base: base, feedDelays: [0, 400, 0])
        let store = AppStore(service: service, persistence: .ephemeral())
        await store.reloadDeck()

        while store.deck.count >= 5, let top = store.deck.first {
            store.swipe(top, .left) // déclenche le complément quand il reste < 5 cartes
        }

        var shoesOnly = FeedFilters()
        shoesOnly.categories = [.shoes]
        await store.apply(shoesOnly)
        try await Task.sleep(for: .milliseconds(600)) // laisse l'ancien complément arriver

        #expect(!store.deck.isEmpty)
        #expect(store.deck.allSatisfy { $0.category == .shoes })
        #expect(!store.isLoadingDeck)
    }

    // MARK: Panier dynamique

    @Test("Une pièce achetée par quelqu'un d'autre disparaît de mon panier")
    func soldItemLeavesCart() async throws {
        let base = MockMarketplaceService.instant()
        let store = AppStore(service: base, persistence: .ephemeral())
        await store.start()
        let garment = try #require(store.deck.first)

        store.swipe(garment, .right)
        await store.waitForPendingCartOperations()
        #expect(store.cart.map(\.id) == [garment.id])

        await base.simulateExternalPurchase(of: garment.id)
        try await Task.sleep(for: .milliseconds(100)) // livraison de l'événement temps réel

        #expect(store.cart.isEmpty)
        #expect(store.lostItems.map(\.id) == [garment.id])
        #expect(store.notices.contains { $0.kind == .soldOut })
    }

    @Test("Revoir les passés ne remontre jamais une pièce likée")
    func reviewPassedSkipsLiked() async throws {
        let store = AppStore(service: MockMarketplaceService.instant(), persistence: .ephemeral())
        await store.reloadDeck()
        let passed = store.deck[0]
        let liked = store.deck[1]

        store.swipe(passed, .left)
        store.swipe(liked, .right)
        await store.waitForPendingCartOperations()
        await store.reviewPassed()

        #expect(store.deck.first?.id == passed.id)
        #expect(!store.deck.contains { $0.id == liked.id })
        #expect(store.passedCount == 0)
    }
}
