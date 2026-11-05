import SwiftUI
import Observation

enum SwipeDirection: Sendable {
    /// Gauche : on passe.
    case left
    /// Droite : on ajoute au panier.
    case right
    /// Haut : achat immédiat.
    case up
}

struct Notice: Identifiable, Equatable {
    enum Kind { case soldOut, success, info, error }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
}

struct CheckoutRequest: Identifiable {
    enum Origin { case buyNow, cartItem, wholeCart }

    let id = UUID()
    let garments: [Garment]
    let origin: Origin
}

enum CheckoutOutcome {
    case success(order: Order, unavailable: [Garment])
    case allUnavailable([Garment])
    case failure(String)
}

/// État global de l'application (source de vérité pour toutes les vues).
@MainActor
@Observable
final class AppStore {
    let service: any MarketplaceService
    private let persistence: LocalPersistence
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pendingBuyNow: Garment?
    /// Opérations panier en cours, chaînées par vêtement : un retrait part
    /// toujours APRÈS l'ajout correspondant, même si le réseau est lent.
    @ObservationIgnored private var cartOperations: [String: Task<Void, Never>] = [:]
    /// Incrémenté à chaque rechargement de la pile : un résultat réseau
    /// obtenu avec d'anciens filtres est ignoré.
    @ObservationIgnored private var deckGeneration = 0
    @ObservationIgnored private var refillTask: Task<Void, Never>?

    // MARK: Pile de swipe
    private(set) var deck: [Garment] = []
    private(set) var isLoadingDeck = false
    private(set) var lastSwipe: (garment: Garment, direction: SwipeDirection)?
    /// Vêtements passés (swipe gauche), dans l'ordre.
    private(set) var passedIDs: [String] = []
    /// Vêtements likés (swipe droite) : ils ne reviennent jamais dans la pile.
    private(set) var likedIDs: Set<String> = []

    // MARK: Panier & commandes
    private(set) var cart: [Garment] = []
    /// Pièces retirées du panier car achetées par quelqu'un d'autre.
    private(set) var lostItems: [Garment] = []
    private(set) var orders: [Order] = []
    private(set) var soldIDs: Set<String> = []

    // MARK: Préférences
    private(set) var filters: FeedFilters
    private(set) var profile: UserProfile

    // MARK: UI
    var notices: [Notice] = []
    var checkout: CheckoutRequest?

    init(service: any MarketplaceService, persistence: LocalPersistence = LocalPersistence()) {
        self.service = service
        self.persistence = persistence
        self.filters = persistence.loadFilters() ?? FeedFilters()
        self.profile = persistence.loadProfile() ?? UserProfile()
    }

    // MARK: - Démarrage

    func start() async {
        guard eventsTask == nil else { return }
        let stream = await service.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
        await refreshCart()
        await refreshOrders()
        await reloadDeck()
    }

    func refreshCart() async {
        do {
            cart = try await service.cart()
            likedIDs.formUnion(cart.map(\.id))
        } catch {
            post(error)
        }
    }

    func refreshOrders() async {
        do {
            orders = try await service.orders()
        } catch {
            post(error)
        }
    }

    // MARK: - Pile

    var purchasedIDs: Set<String> {
        Set(orders.flatMap { $0.items.map(\.id) })
    }

    var passedCount: Int { passedIDs.count }
    var canUndo: Bool { lastSwipe != nil }

    private func excludedIDs() -> Set<String> {
        var ids = Set(passedIDs).union(likedIDs).union(purchasedIDs).union(deck.map(\.id))
        if let pending = pendingBuyNow { ids.insert(pending.id) }
        return ids
    }

    func reloadDeck() async {
        deckGeneration += 1
        let generation = deckGeneration
        // Un complément de pile lancé avec les anciens filtres ne doit plus arriver.
        refillTask?.cancel()
        refillTask = nil

        isLoadingDeck = true
        deck = []
        let currentFilters = filters
        let excluded = excludedIDs()
        do {
            let items = try await service.feed(filters: currentFilters, excluding: excluded, limit: 20)
            guard generation == deckGeneration else { return }
            deck = items
        } catch {
            if generation == deckGeneration { post(error) }
        }
        if generation == deckGeneration { isLoadingDeck = false }
    }

    private func refillDeckIfNeeded() {
        guard deck.count < 5, refillTask == nil, !isLoadingDeck else { return }
        let generation = deckGeneration
        let currentFilters = filters
        let excluded = excludedIDs()
        refillTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.deckGeneration { self.refillTask = nil }
            }
            guard let more = try? await self.service.feed(filters: currentFilters, excluding: excluded, limit: 20),
                  !Task.isCancelled,
                  generation == self.deckGeneration else { return }
            // Exclut aussi ce qui a été swipé pendant le chargement.
            let existing = self.excludedIDs()
            self.deck.append(contentsOf: more.filter { !existing.contains($0.id) })
        }
    }

    /// Attend la fin du complément de pile en cours (utile pour les tests).
    func waitForDeckRefill() async {
        await refillTask?.value
    }

    /// Version la plus récente d'un vêtement (compteur panier, statut…).
    func liveVersion(of garment: Garment) -> Garment {
        var result = deck.first(where: { $0.id == garment.id })
            ?? cart.first(where: { $0.id == garment.id })
            ?? garment
        if soldIDs.contains(garment.id) { result.status = .sold }
        return result
    }

    func isUnavailable(_ garmentID: String) -> Bool {
        soldIDs.contains(garmentID)
    }

    // MARK: - Swipe

    func swipe(_ garment: Garment, _ direction: SwipeDirection) {
        deck.removeAll { $0.id == garment.id }
        defer { refillDeckIfNeeded() }

        let isSold = garment.status == .sold || soldIDs.contains(garment.id)
        if isSold && direction != .left {
            post(Notice(kind: .soldOut, title: "Trop tard ! 💔", message: "« \(garment.title) » vient d'être vendu."))
            Haptics.warning()
            return
        }

        switch direction {
        case .left:
            passedIDs.removeAll { $0 == garment.id }
            passedIDs.append(garment.id)
            lastSwipe = (garment, .left)
            Haptics.impact(.light)
        case .right:
            likedIDs.insert(garment.id)
            lastSwipe = (garment, .right)
            addToCart(garment)
            Haptics.impact(.medium)
        case .up:
            lastSwipe = nil
            pendingBuyNow = garment
            checkout = CheckoutRequest(garments: [garment], origin: .buyNow)
            Haptics.impact(.heavy)
        }
    }

    /// Annule le dernier swipe (gauche ou droite), comme le bouton « retour » de Tinder.
    func undoLastSwipe() {
        guard let last = lastSwipe else { return }
        lastSwipe = nil
        let garment = last.garment
        switch last.direction {
        case .left:
            passedIDs.removeAll { $0 == garment.id }
        case .right:
            likedIDs.remove(garment.id)
            cart.removeAll { $0.id == garment.id }
            sendRemoveFromCart(garment.id)
        case .up:
            break
        }
        guard !soldIDs.contains(garment.id) else {
            post(Notice(kind: .soldOut, title: "Trop tard ! 💔", message: "« \(garment.title) » a été vendu entre-temps."))
            return
        }
        // `garment` a été capturé avant l'ajout au panier : son compteur est déjà le bon.
        deck.insert(garment, at: 0)
        Haptics.impact(.light)
    }

    /// Remet dans la pile les vêtements passés encore disponibles,
    /// sans jamais remontrer ceux déjà likés ou achetés.
    func reviewPassed() async {
        let ids = passedIDs
        guard !ids.isEmpty else { return }
        do {
            let items = try await service.garments(ids: ids)
            let soldPassed = Set(items.filter { !$0.isAvailable }.map(\.id))
            let candidates = items.filter {
                $0.isAvailable && !likedIDs.contains($0.id) && !purchasedIDs.contains($0.id) && filters.matches($0)
            }
            let candidateIDs = Set(candidates.map(\.id))
            passedIDs.removeAll { candidateIDs.contains($0) || soldPassed.contains($0) }
            let existing = Set(deck.map(\.id))
            deck.insert(contentsOf: candidates.filter { !existing.contains($0.id) }, at: 0)
            lastSwipe = nil

            if candidates.isEmpty {
                post(Notice(kind: .info, title: "Rien à revoir", message: "Les vêtements passés ont été vendus ou ne correspondent plus à tes filtres."))
            } else {
                let plural = candidates.count > 1 ? "s" : ""
                post(Notice(kind: .info, title: "Seconde chance 👀", message: "\(candidates.count) vêtement\(plural) passé\(plural) remis dans la pile."))
            }
        } catch {
            post(error)
        }
    }

    // MARK: - Panier

    var cartSubtotalCents: Int {
        cart.reduce(0) { $0 + $1.priceCents }
    }

    private func addToCart(_ garment: Garment) {
        cart.removeAll { $0.id == garment.id }
        var optimistic = garment
        optimistic.cartCount += 1
        cart.insert(optimistic, at: 0)

        enqueueCartOperation(for: garment.id) { [weak self] in
            guard let self else { return }
            // Swipe annulé avant l'envoi : inutile de prévenir le serveur.
            guard self.cart.contains(where: { $0.id == garment.id }) else { return }
            do {
                let updated = try await self.service.addToCart(garment.id)
                if let index = self.cart.firstIndex(where: { $0.id == updated.id }) {
                    self.cart[index] = updated
                }
            } catch {
                self.cart.removeAll { $0.id == garment.id }
                if (error as? MarketplaceError) == .alreadySold {
                    self.soldIDs.insert(garment.id)
                    self.post(Notice(kind: .soldOut, title: "Trop tard ! 💔", message: "« \(garment.title) » vient d'être vendu."))
                } else {
                    self.post(error)
                }
            }
        }
    }

    func removeFromCart(_ garment: Garment) {
        cart.removeAll { $0.id == garment.id }
        sendRemoveFromCart(garment.id)
    }

    private func sendRemoveFromCart(_ garmentID: String) {
        enqueueCartOperation(for: garmentID) { [weak self] in
            try? await self?.service.removeFromCart(garmentID)
        }
    }

    /// Chaîne les appels serveur d'un même vêtement pour qu'ils arrivent dans l'ordre.
    private func enqueueCartOperation(for garmentID: String, _ operation: @escaping @MainActor () async -> Void) {
        let previous = cartOperations[garmentID]
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        cartOperations[garmentID] = task
        Task { @MainActor [weak self] in
            await task.value
            // Nettoyage si aucune opération plus récente n'a été ajoutée.
            if let self, self.cartOperations[garmentID] == task {
                self.cartOperations[garmentID] = nil
            }
        }
    }

    /// Attend que toutes les opérations panier soient parties au serveur (utile pour les tests).
    func waitForPendingCartOperations() async {
        // La dernière tâche de chaque vêtement attend déjà les précédentes.
        for task in Array(cartOperations.values) {
            await task.value
        }
    }

    func clearLostItems() {
        lostItems.removeAll()
    }

    func buy(_ garment: Garment) {
        checkout = CheckoutRequest(garments: [garment], origin: .cartItem)
    }

    func buyWholeCart() {
        guard !cart.isEmpty else { return }
        checkout = CheckoutRequest(garments: cart, origin: .wholeCart)
    }

    // MARK: - Paiement

    /// Devis du serveur : l'app n'a aucune règle de prix codée en dur.
    func quote(for garments: [Garment]) async throws -> PriceQuote {
        try await service.quote(garments.map(\.id))
    }

    func confirmCheckout(_ request: CheckoutRequest) async -> CheckoutOutcome {
        guard profile.isReadyForCheckout, let payment = profile.payment else {
            return .failure("Complète ton profil (coordonnées, adresse et paiement) pour acheter.")
        }
        let details = CheckoutDetails(
            buyerName: profile.fullName,
            address: profile.address,
            deliveryMethod: profile.deliveryMethod,
            relayPoint: profile.relayPoint,
            payment: payment
        )
        do {
            let result = try await service.purchase(request.garments.map(\.id), details: details)
            let boughtIDs = Set(result.order?.items.map(\.id) ?? [])
            let unavailableIDs = Set(result.unavailable.map(\.id))

            cart.removeAll { boughtIDs.contains($0.id) || unavailableIDs.contains($0.id) }
            deck.removeAll { boughtIDs.contains($0.id) || unavailableIDs.contains($0.id) }
            soldIDs.formUnion(boughtIDs)
            soldIDs.formUnion(unavailableIDs)
            pendingBuyNow = nil

            guard let order = result.order else {
                return .allUnavailable(result.unavailable)
            }
            if !orders.contains(where: { $0.id == order.id }) {
                orders.insert(order, at: 0)
            }
            return .success(order: order, unavailable: result.unavailable)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Appelé à la fermeture de la feuille de paiement.
    /// Si l'achat express (swipe haut) a été annulé, la carte revient sur la pile.
    func checkoutDismissed() {
        guard let garment = pendingBuyNow else { return }
        pendingBuyNow = nil
        guard !soldIDs.contains(garment.id), !purchasedIDs.contains(garment.id) else { return }
        deck.insert(garment, at: 0)
    }

    // MARK: - Préférences

    func apply(_ newFilters: FeedFilters) async {
        filters = newFilters
        persistence.saveFilters(newFilters)
        lastSwipe = nil
        await reloadDeck()
    }

    func updateProfile(_ newProfile: UserProfile) {
        profile = newProfile
        persistence.saveProfile(newProfile)
    }

    func setDeliveryMethod(_ method: DeliveryMethod) {
        var copy = profile
        copy.deliveryMethod = method
        updateProfile(copy)
    }

    // MARK: - Temps réel

    private func handle(_ event: MarketplaceEvent) {
        switch event {
        case let .garmentSold(id, title, byCurrentUser):
            soldIDs.insert(id)
            if let index = deck.firstIndex(where: { $0.id == id }) {
                // La carte du dessus reste affichée avec un bandeau « VENDU »
                // pour ne pas la faire disparaître sous le doigt de l'utilisateur.
                if index == 0 {
                    deck[0].status = .sold
                } else {
                    deck.remove(at: index)
                }
            }
            guard let garment = cart.first(where: { $0.id == id }) else { return }
            cart.removeAll { $0.id == id }
            guard !byCurrentUser else { return }
            var lost = garment
            lost.status = .sold
            lostItems.removeAll { $0.id == id }
            lostItems.insert(lost, at: 0)
            post(Notice(
                kind: .soldOut,
                title: "Trop tard… 💔",
                message: "« \(title) » vient d'être acheté par quelqu'un d'autre. Il a été retiré de ton panier."
            ))
            Haptics.warning()

        case let .cartCountChanged(id, count):
            if let index = deck.firstIndex(where: { $0.id == id }) {
                deck[index].cartCount = count
            }
            if let index = cart.firstIndex(where: { $0.id == id }) {
                cart[index].cartCount = count
            }

        case let .orderUpdated(order):
            let previous = orders.first(where: { $0.id == order.id })?.status
            if let index = orders.firstIndex(where: { $0.id == order.id }) {
                orders[index] = order
            } else {
                orders.insert(order, at: 0)
            }
            if previous != order.status, order.status == .shipped || order.status == .delivered {
                post(Notice(kind: .info, title: "📦 Commande \(order.number)", message: order.statusLabel))
            }
        }
    }

    // MARK: - Notifications in-app

    func post(_ notice: Notice) {
        notices.append(notice)
    }

    func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    private func post(_ error: Error) {
        post(Notice(kind: .error, title: "Oups", message: error.localizedDescription))
    }
}
