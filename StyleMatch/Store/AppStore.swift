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
    /// Paiement accepté, commande pas encore confirmée par le serveur.
    case pending(String)
    case failure(String)
}

/// Étape du paiement : soit il faut présenter la feuille de paiement Stripe,
/// soit c'est déjà terminé (mode démo, erreur, pièces indisponibles).
enum PaymentStep {
    case ready(PaymentPreparation, CheckoutDetails)
    case finished(CheckoutOutcome)
}

/// État global de l'application (source de vérité pour toutes les vues).
@MainActor
@Observable
final class AppStore {
    let service: any MarketplaceService
    let auth: any AuthProvider
    private let persistence: LocalPersistence
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoadedOnce = false
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

    /// Pièces en cours de paiement par MOI (leur vente n'est pas un « Trop tard »).
    private(set) var payingIDs: Set<String> = []

    // MARK: Compte & préférences
    private(set) var account: Account?
    private(set) var filters: FeedFilters
    private(set) var profile: UserProfile

    // MARK: UI
    var notices: [Notice] = []
    var checkout: CheckoutRequest?
    /// Affiche l'écran de connexion (swipe droite / haut sans compte…).
    var showSignIn = false

    init(
        service: any MarketplaceService,
        auth: any AuthProvider = DemoAuthProvider(),
        persistence: LocalPersistence = LocalPersistence()
    ) {
        self.service = service
        self.auth = auth
        self.persistence = persistence
        self.filters = persistence.loadFilters() ?? FeedFilters()
        self.profile = persistence.loadProfile() ?? UserProfile()
    }

    var isSignedIn: Bool { account != nil }
    var isAdmin: Bool { account?.isAdmin ?? false }
    var usesExternalPaymentSheet: Bool { service.usesExternalPaymentSheet }

    // MARK: - Démarrage

    func start() async {
        guard eventsTask == nil else { return }
        let stream = await service.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }

        // Le premier état de connexion est attendu pour charger les bonnes données.
        let accounts = await auth.accountChanges()
        var iterator = accounts.makeAsyncIterator()
        let first: Account? = (await iterator.next()) ?? nil
        await accountDidChange(first)
        authTask = Task { [weak self, iterator] in
            var remaining = iterator
            while let next = await remaining.next() {
                await self?.accountDidChange(next)
            }
        }
    }

    private func accountDidChange(_ newAccount: Account?) async {
        let changed = newAccount?.id != account?.id
        account = newAccount
        guard changed || !hasLoadedOnce else { return }
        hasLoadedOnce = true
        lastSwipe = nil
        lostItems = []

        if newAccount != nil {
            if let history = try? await service.swipeHistory() {
                passedIDs = history.passed
                likedIDs = history.liked
            }
            await syncProfileFromServer()
            showSignIn = false
        } else {
            cart = []
            orders = []
            passedIDs = []
            likedIDs = []
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

        if direction != .left && !isSignedIn {
            // Panier et achat demandent un compte : la carte revient sur la pile.
            deck.insert(garment, at: 0)
            showSignIn = true
            return
        }

        switch direction {
        case .left:
            passedIDs.removeAll { $0 == garment.id }
            passedIDs.append(garment.id)
            lastSwipe = (garment, .left)
            sendSwipe(garment.id, .left)
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
            sendForgetSwipe(garment.id)
        case .right:
            likedIDs.remove(garment.id)
            cart.removeAll { $0.id == garment.id }
            sendRemoveFromCart(garment.id)
            sendForgetSwipe(garment.id)
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
            if isSignedIn {
                try? await service.forgetSwipes(Array(candidateIDs))
            }
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
                try? await self.service.recordSwipe(garment.id, direction: .right)
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

    private func sendSwipe(_ garmentID: String, _ direction: SwipeDirection) {
        guard isSignedIn else { return }
        enqueueCartOperation(for: garmentID) { [weak self] in
            try? await self?.service.recordSwipe(garmentID, direction: direction)
        }
    }

    private func sendForgetSwipe(_ garmentID: String) {
        guard isSignedIn else { return }
        enqueueCartOperation(for: garmentID) { [weak self] in
            try? await self?.service.forgetSwipes([garmentID])
        }
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

    /// Parties du profil nécessaires pour acheter (avec Stripe, la carte se saisit au paiement).
    var profileParts: [UserProfile.Part] {
        usesExternalPaymentSheet ? [.personal, .address] : UserProfile.Part.allCases
    }

    var missingCheckoutParts: [UserProfile.Part] {
        profileParts.filter { !profile.isComplete($0) }
    }

    /// 1re étape : réserve les pièces et prépare le paiement.
    func preparePayment(_ request: CheckoutRequest) async -> PaymentStep {
        guard isSignedIn else {
            showSignIn = true
            return .finished(.failure("Connecte-toi pour acheter."))
        }
        guard missingCheckoutParts.isEmpty else {
            return .finished(.failure("Complète ton profil (coordonnées et adresse) pour acheter."))
        }
        let details = CheckoutDetails(
            buyerName: profile.fullName,
            address: profile.address,
            deliveryMethod: profile.deliveryMethod,
            relayPoint: profile.relayPoint,
            payment: usesExternalPaymentSheet ? nil : profile.payment
        )
        let ids = request.garments.map(\.id)
        payingIDs.formUnion(ids)
        do {
            let preparation = try await service.preparePayment(ids, details: details)
            markUnavailable(preparation.unavailable)
            guard !preparation.reservedIDs.isEmpty else {
                payingIDs.subtract(ids)
                pendingBuyNow = nil
                return .finished(.allUnavailable(preparation.unavailable))
            }
            return .ready(preparation, details)
        } catch {
            payingIDs.subtract(ids)
            return .finished(.failure(error.localizedDescription))
        }
    }

    /// 2e étape (après la feuille de paiement) : récupère la commande.
    func finishPayment(_ preparation: PaymentPreparation, details: CheckoutDetails) async -> CheckoutOutcome {
        defer { payingIDs.subtract(preparation.reservedIDs) }
        do {
            let result = try await service.completePayment(preparation, details: details)
            return applyPurchase(result)
        } catch MarketplaceError.paymentPending {
            pendingBuyNow = nil
            cart.removeAll { preparation.reservedIDs.contains($0.id) }
            deck.removeAll { preparation.reservedIDs.contains($0.id) }
            Task {
                try? await Task.sleep(for: .seconds(10))
                await refreshOrders()
            }
            return .pending(MarketplaceError.paymentPending.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Feuille de paiement fermée sans payer : les pièces sont libérées.
    func abandonPayment(_ preparation: PaymentPreparation) async {
        payingIDs.subtract(preparation.reservedIDs)
        await service.cancelPayment(preparation)
    }

    /// Paiement en une étape (mode démo, tests).
    func confirmCheckout(_ request: CheckoutRequest) async -> CheckoutOutcome {
        switch await preparePayment(request) {
        case .finished(let outcome):
            return outcome
        case let .ready(preparation, details):
            return await finishPayment(preparation, details: details)
        }
    }

    private func markUnavailable(_ garments: [Garment]) {
        let ids = Set(garments.map(\.id))
        guard !ids.isEmpty else { return }
        soldIDs.formUnion(ids)
        cart.removeAll { ids.contains($0.id) }
        deck.removeAll { ids.contains($0.id) }
    }

    private func applyPurchase(_ result: PurchaseResult) -> CheckoutOutcome {
        let boughtIDs = Set(result.order?.items.map(\.id) ?? [])
        cart.removeAll { boughtIDs.contains($0.id) }
        deck.removeAll { boughtIDs.contains($0.id) }
        soldIDs.formUnion(boughtIDs)
        markUnavailable(result.unavailable)
        pendingBuyNow = nil

        guard let order = result.order else {
            return .allUnavailable(result.unavailable)
        }
        if !orders.contains(where: { $0.id == order.id }) {
            orders.insert(order, at: 0)
        }
        return .success(order: order, unavailable: result.unavailable)
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
        guard isSignedIn else { return }
        Task { try? await service.saveProfile(newProfile) }
    }

    /// Le serveur fait foi pour les coordonnées ; la carte du mode démo reste locale.
    private func syncProfileFromServer() async {
        guard let server = try? await service.loadProfile() else {
            if isSignedIn { try? await service.saveProfile(profile) }
            return
        }
        let serverHasData = server.isPersonalInfoComplete || server.address.isComplete
        if serverHasData {
            var merged = server
            merged.payment = profile.payment
            if merged.email.isEmpty { merged.email = account?.email ?? profile.email }
            profile = merged
            persistence.saveProfile(merged)
        } else {
            if profile.email.isEmpty, let email = account?.email { profile.email = email }
            var withNames = profile
            if withNames.firstName.isEmpty { withNames.firstName = server.firstName }
            if withNames.lastName.isEmpty { withNames.lastName = server.lastName }
            profile = withNames
            persistence.saveProfile(withNames)
            try? await service.saveProfile(withNames)
        }
    }

    // MARK: - Connexion

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws {
        try await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
    }

    func sendEmailCode(to email: String) async throws {
        try await auth.sendEmailCode(to: email)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        try await auth.verifyEmailCode(email: email, code: code)
    }

    func signOut() async {
        do {
            try await auth.signOut()
            persistence.clearProfile()
            profile = UserProfile()
        } catch {
            post(error)
        }
    }

    /// Suppression définitive du compte (profil, panier, historique).
    func deleteAccount() async -> Bool {
        do {
            try await auth.deleteAccount()
            persistence.clearProfile()
            profile = UserProfile()
            post(Notice(kind: .info, title: "Compte supprimé", message: "Tes données personnelles ont été effacées."))
            return true
        } catch {
            post(error)
            return false
        }
    }

    // MARK: - Boutique

    func adminCatalogue() async throws -> [Garment] { try await service.adminCatalogue() }
    func saveGarment(_ draft: GarmentDraft) async throws -> Garment { try await service.saveGarment(draft) }
    func setGarmentWithdrawn(_ id: String, withdrawn: Bool) async throws {
        try await service.setGarmentWithdrawn(id, withdrawn: withdrawn)
    }
    func adminOrders() async throws -> [Order] { try await service.adminOrders() }
    func updateOrder(_ id: String, status: OrderStatus, trackingNumber: String?) async throws -> Order {
        try await service.updateOrder(id, status: status, trackingNumber: trackingNumber)
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
            // Ma propre commande (le webhook peut arriver avant la fin du paiement).
            guard !byCurrentUser, !payingIDs.contains(id), !purchasedIDs.contains(id) else { return }
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
