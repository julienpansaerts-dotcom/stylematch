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
        await store.start()
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
        await store.start()
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
        await store.start()

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

    // MARK: Compte

    @Test("Sans compte, swiper à droite remet la carte et demande la connexion")
    func signedOutRightSwipe() async throws {
        let base = MockMarketplaceService.instant()
        let store = AppStore(service: base, auth: DemoAuthProvider(signedIn: false), persistence: .ephemeral())
        await store.start()
        let garment = try #require(store.deck.first)

        store.swipe(garment, .right)
        await store.waitForPendingCartOperations()

        #expect(store.showSignIn)
        #expect(store.deck.first?.id == garment.id)
        #expect(store.cart.isEmpty)
        #expect(try await base.cart().isEmpty)

        // Passer reste possible sans compte.
        store.swipe(garment, .left)
        #expect(store.passedCount == 1)
    }

    @Test("Les swipes sont enregistrés sur le serveur pour ne jamais remontrer une pièce likée")
    func swipesAreSynced() async throws {
        let base = MockMarketplaceService.instant()
        let store = AppStore(service: base, persistence: .ephemeral())
        await store.start()
        let passed = store.deck[0]
        let liked = store.deck[1]

        store.swipe(passed, .left)
        store.swipe(liked, .right)
        await store.waitForPendingCartOperations()

        let history = try await base.swipeHistory()
        #expect(history.passed == [passed.id])
        #expect(history.liked == [liked.id])

        // Un nouvel appareil (nouveau store) retrouve le même historique.
        let other = AppStore(service: base, persistence: .ephemeral())
        await other.start()
        #expect(!other.deck.contains { $0.id == liked.id || $0.id == passed.id })
        #expect(other.passedCount == 1)
    }

    // MARK: Paiement

    @Test("Acheter tout le panier crée la commande et vide le panier")
    func checkoutWholeCart() async throws {
        let store = AppStore(service: MockMarketplaceService.instant(), persistence: .ephemeral())
        await store.start()
        var profile = UserProfile()
        profile.firstName = "Julien"
        profile.lastName = "Test"
        profile.email = "julien@test.fr"
        profile.address = ShippingAddress(line1: "1 rue du Test", postalCode: "75001", city: "Paris")
        profile.payment = PaymentMethod(kind: .applePay)
        store.updateProfile(profile)

        let pieces = Array(store.deck.prefix(2))
        for piece in pieces { store.swipe(piece, .right) }
        await store.waitForPendingCartOperations()

        let outcome = await store.confirmCheckout(CheckoutRequest(garments: store.cart, origin: .wholeCart))
        guard case let .success(order, unavailable) = outcome else {
            Issue.record("achat refusé : \(outcome)")
            return
        }
        #expect(Set(order.items.map(\.id)) == Set(pieces.map(\.id)))
        #expect(order.buyerName == "Julien Test")
        #expect(unavailable.isEmpty)
        #expect(store.cart.isEmpty)
        #expect(store.orders.first?.id == order.id)
    }

    @Test("Sans adresse, l'achat est refusé avec un message clair")
    func checkoutRequiresAddress() async throws {
        let store = AppStore(service: MockMarketplaceService.instant(), persistence: .ephemeral())
        await store.start()
        let garment = try #require(store.deck.first)
        let outcome = await store.confirmCheckout(CheckoutRequest(garments: [garment], origin: .buyNow))
        guard case .failure = outcome else {
            Issue.record("l'achat aurait dû être refusé")
            return
        }
        #expect(!store.missingCheckoutParts.isEmpty)
    }

    // MARK: Boutique

    @Test("La boutique publie une pièce qui apparaît dans le fil")
    func adminPublishesGarment() async throws {
        let base = MockMarketplaceService.instant()
        let store = AppStore(service: base, persistence: .ephemeral())
        await store.start()
        #expect(store.isAdmin) // compte démo = boutique

        var draft = GarmentDraft()
        draft.title = "Gilet test"
        draft.priceEuros = "19,90"
        draft.category = .knitwear
        draft.newPhotos = [Data([0xFF, 0xD8, 0xFF])]
        #expect(draft.isValid)
        #expect(draft.priceCents == 1990)

        let saved = try await store.saveGarment(draft)
        let feed = try await base.feed(filters: FeedFilters(), excluding: [], limit: 100)
        #expect(feed.first?.id == saved.id)

        try await store.setGarmentWithdrawn(saved.id, withdrawn: true)
        let after = try await base.feed(filters: FeedFilters(), excluding: [], limit: 100)
        #expect(!after.contains { $0.id == saved.id })
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
        await store.start()
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
