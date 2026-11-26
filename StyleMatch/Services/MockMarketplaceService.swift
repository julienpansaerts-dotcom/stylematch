import Foundation

/// Backend simulé en mémoire.
///
/// Il reproduit le comportement du vrai serveur, y compris l'activité des
/// AUTRES utilisateurs : des gens ajoutent des pièces à leur panier (ce qui
/// les rend HOT) et achètent parfois une pièce qui est dans TON panier —
/// elle disparaît alors de ton panier en direct (« Trop tard ! »).
actor MockMarketplaceService: MarketplaceService {
    nonisolated let usesExternalPaymentSheet = false

    private var catalogue: [String: Garment]
    private var feedOrder: [String]
    private var myCart: [String] = []
    private var myOrders: [Order]
    private var swipes: [String: SwipeDirection] = [:]
    private var swipeOrder: [String] = []
    private var storedProfile: UserProfile?
    private var subscribers: [UUID: AsyncStream<MarketplaceEvent>.Continuation] = [:]
    private var simulationTask: Task<Void, Never>?
    private let simulateOtherUsers: Bool
    private let latency: ClosedRange<Int>
    private let paymentDelay: Int
    private var orderCounter = 41

    /// - Parameters:
    ///   - simulateOtherUsers: simule l'activité des autres acheteurs (désactivé dans les tests).
    ///   - latency: délai réseau simulé, en millisecondes.
    ///   - paymentDelay: durée simulée de l'autorisation bancaire, en millisecondes.
    init(simulateOtherUsers: Bool = true, latency: ClosedRange<Int> = 120...300, paymentDelay: Int = 900) {
        let items = MockCatalogue.makeGarments()
        self.catalogue = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.feedOrder = items.map(\.id)
        self.myOrders = MockCatalogue.makePastOrders()
        self.simulateOtherUsers = simulateOtherUsers
        self.latency = latency
        self.paymentDelay = paymentDelay
    }

    deinit {
        simulationTask?.cancel()
    }

    // MARK: - Lecture

    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment] {
        try await networkDelay()
        let result = feedOrder
            .compactMap { catalogue[$0] }
            .filter {
                $0.isAvailable && !excluding.contains($0.id) && !myCart.contains($0.id)
                    && swipes[$0.id] == nil && filters.matches($0)
            }
        return Array(result.prefix(limit))
    }

    func garments(ids: [String]) async throws -> [Garment] {
        try await networkDelay()
        return ids.compactMap { catalogue[$0] }
    }

    func swipeHistory() async throws -> SwipeHistory {
        try await networkDelay()
        return SwipeHistory(
            passed: swipeOrder.filter { swipes[$0] == .left },
            liked: Set(swipeOrder.filter { swipes[$0] == .right || swipes[$0] == .up })
        )
    }

    func recordSwipe(_ garmentID: String, direction: SwipeDirection) async throws {
        try await networkDelay()
        swipeOrder.removeAll { $0 == garmentID }
        swipeOrder.append(garmentID)
        swipes[garmentID] = direction
    }

    func forgetSwipes(_ garmentIDs: [String]) async throws {
        try await networkDelay()
        for id in garmentIDs { swipes[id] = nil }
        swipeOrder.removeAll { garmentIDs.contains($0) }
    }

    func loadProfile() async throws -> UserProfile? {
        try await networkDelay()
        return storedProfile
    }

    func saveProfile(_ profile: UserProfile) async throws {
        try await networkDelay()
        storedProfile = profile
    }

    func cart() async throws -> [Garment] {
        try await networkDelay()
        return myCart.compactMap { catalogue[$0] }
    }

    func orders() async throws -> [Order] {
        try await networkDelay()
        return myOrders
    }

    // MARK: - Panier

    func addToCart(_ garmentID: String) async throws -> Garment {
        try await networkDelay()
        guard var garment = catalogue[garmentID] else { throw MarketplaceError.notFound }
        guard garment.isAvailable else { throw MarketplaceError.alreadySold }
        if !myCart.contains(garmentID) {
            myCart.insert(garmentID, at: 0)
            garment.cartCount += 1
            catalogue[garmentID] = garment
            broadcast(.cartCountChanged(id: garmentID, count: garment.cartCount))
        }
        return garment
    }

    func removeFromCart(_ garmentID: String) async throws {
        try await networkDelay()
        guard let index = myCart.firstIndex(of: garmentID) else { return }
        myCart.remove(at: index)
        if var garment = catalogue[garmentID] {
            garment.cartCount = max(0, garment.cartCount - 1)
            catalogue[garmentID] = garment
            broadcast(.cartCountChanged(id: garmentID, count: garment.cartCount))
        }
    }

    // MARK: - Achat

    func quote(_ garmentIDs: [String]) async throws -> PriceQuote {
        try await networkDelay()
        return ServerPricing.quote(for: garmentIDs.compactMap { catalogue[$0] }, requestedIDs: garmentIDs)
    }

    func preparePayment(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PaymentPreparation {
        let quote = try await quote(garmentIDs)
        return PaymentPreparation(
            paymentIntentID: nil,
            clientSecret: nil, // pas de feuille Stripe en mode démo
            reservedIDs: garmentIDs,
            unavailable: [],
            totalCents: quote.total(for: details.deliveryMethod)
        )
    }

    func completePayment(_ preparation: PaymentPreparation, details: CheckoutDetails) async throws -> PurchaseResult {
        try await purchase(preparation.reservedIDs, details: details)
    }

    func cancelPayment(_ preparation: PaymentPreparation) async {}

    /// Achat atomique (utilisé par le mode démo et les tests).
    func purchase(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PurchaseResult {
        // Simule l'autorisation bancaire.
        try await Task.sleep(for: .milliseconds(paymentDelay))

        // ⚠️ Section critique : aucune suspension (`await`) entre la vérification
        // et le marquage « vendu ». L'acteur garantit qu'aucun autre achat ne
        // peut s'intercaler — l'équivalent du `SELECT … FOR UPDATE` côté serveur.
        var bought: [Garment] = []
        var unavailable: [Garment] = []
        for id in garmentIDs {
            guard var garment = catalogue[id] else { continue }
            if garment.isAvailable {
                garment.status = .sold
                catalogue[id] = garment
                bought.append(garment)
            } else {
                unavailable.append(garment)
            }
        }
        myCart.removeAll { garmentIDs.contains($0) }

        guard !bought.isEmpty else {
            return PurchaseResult(order: nil, unavailable: unavailable)
        }

        let subtotal = bought.reduce(0) { $0 + $1.priceCents }
        orderCounter += 1
        let now = Date()
        let order = Order(
            id: UUID().uuidString,
            number: "SM-2026-\(String(format: "%04d", orderCounter))",
            createdAt: now,
            items: bought,
            subtotalCents: subtotal,
            shippingCents: ServerPricing.shipping(for: details.deliveryMethod),
            serviceFeeCents: ServerPricing.serviceFee(subtotal: subtotal),
            deliveryMethod: details.deliveryMethod,
            shippingAddress: details.address,
            relayPoint: details.relayPoint,
            paymentSummary: details.payment?.summary ?? "Carte bancaire",
            trackingNumber: nil,
            status: .confirmed,
            timeline: [OrderStatusEvent(status: .confirmed, date: now)],
            buyerName: details.buyerName
        )
        myOrders.insert(order, at: 0)

        for garment in bought {
            broadcast(.garmentSold(id: garment.id, title: garment.title, byCurrentUser: true))
        }
        return PurchaseResult(order: order, unavailable: unavailable)
    }

    // MARK: - Boutique

    func adminCatalogue() async throws -> [Garment] {
        try await networkDelay()
        return feedOrder.compactMap { catalogue[$0] }
    }

    func saveGarment(_ draft: GarmentDraft) async throws -> Garment {
        try await networkDelay()
        guard let priceCents = draft.priceCents else { throw MarketplaceError.server("Prix invalide.") }
        // Les nouvelles photos sont écrites dans le cache de l'app (mode démo).
        var photoURLs = draft.existingPhotos
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stylematch-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for data in draft.newPhotos {
            let url = folder.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: url)
            photoURLs.append(url)
        }
        let id = draft.id ?? UUID().uuidString
        let previous = catalogue[id]
        let garment = Garment(
            id: id,
            title: draft.title.trimmed,
            brand: draft.brand.trimmed,
            summary: draft.summary.trimmed,
            details: draft.details.trimmed,
            measurements: draft.measurements.trimmed.isEmpty ? nil : draft.measurements.trimmed,
            size: draft.size,
            gender: draft.gender,
            category: draft.category,
            condition: draft.condition,
            color: draft.color,
            priceCents: priceCents,
            photos: photoURLs.map { .remote($0) },
            cartCount: previous?.cartCount ?? 0,
            status: previous?.status ?? .available
        )
        catalogue[id] = garment
        if previous == nil { feedOrder.insert(id, at: 0) }
        return garment
    }

    func setGarmentWithdrawn(_ garmentID: String, withdrawn: Bool) async throws {
        try await networkDelay()
        guard var garment = catalogue[garmentID], garment.status != .sold else { return }
        garment.status = withdrawn ? .withdrawn : .available
        catalogue[garmentID] = garment
        if withdrawn {
            myCart.removeAll { $0 == garmentID }
            broadcast(.garmentSold(id: garmentID, title: garment.title, byCurrentUser: false))
        }
    }

    func adminOrders() async throws -> [Order] {
        try await networkDelay()
        return myOrders
    }

    func updateOrder(_ orderID: String, status: OrderStatus, trackingNumber: String?) async throws -> Order {
        try await networkDelay()
        guard let index = myOrders.firstIndex(where: { $0.id == orderID }) else { throw MarketplaceError.notFound }
        if myOrders[index].status != status {
            myOrders[index].status = status
            myOrders[index].timeline.append(OrderStatusEvent(status: status, date: Date()))
        }
        myOrders[index].trackingNumber = trackingNumber
        broadcast(.orderUpdated(myOrders[index]))
        return myOrders[index]
    }

    // MARK: - Temps réel

    func events() -> AsyncStream<MarketplaceEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: MarketplaceEvent.self)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        startSimulationIfNeeded()
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast(_ event: MarketplaceEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func networkDelay() async throws {
        try await Task.sleep(for: .milliseconds(Int.random(in: latency)))
    }

    // MARK: - Simulation des autres utilisateurs

    private func startSimulationIfNeeded() {
        guard simulateOtherUsers, simulationTask == nil else { return }
        simulationTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
                guard let self else { return }
                tick += 1
                await self.simulateTick(tick)
            }
        }
    }

    private func simulateTick(_ tick: Int) {
        simulateCartActivity()
        if tick % 10 == 0 { simulateSomeoneElseBuying(nil) }
        if tick % 4 == 0 { advanceOrders() }
    }

    /// Quelqu'un ajoute (ou retire) une pièce de son panier.
    private func simulateCartActivity() {
        let available = catalogue.values.filter(\.isAvailable)
        guard var garment = available.randomElement() else { return }
        if Double.random(in: 0...1) < 0.75 {
            garment.cartCount += 1
        } else {
            // On ne descend jamais sous 1 si la pièce est dans mon panier.
            let floor = myCart.contains(garment.id) ? 1 : 0
            garment.cartCount = max(floor, garment.cartCount - 1)
        }
        catalogue[garment.id] = garment
        broadcast(.cartCountChanged(id: garment.id, count: garment.cartCount))
    }

    /// Simule l'achat d'une pièce précise par un autre utilisateur (tests).
    func simulateExternalPurchase(of garmentID: String) {
        simulateSomeoneElseBuying(garmentID)
    }

    /// Un autre utilisateur achète une pièce — parfois une pièce de mon panier.
    private func simulateSomeoneElseBuying(_ forcedID: String?) {
        let target: String?
        if let forcedID {
            target = forcedID
        } else if !myCart.isEmpty && Double.random(in: 0...1) < 0.4 {
            target = myCart.randomElement()
        } else {
            target = catalogue.values.filter(\.isAvailable).randomElement()?.id
        }
        guard let id = target, var garment = catalogue[id], garment.isAvailable else { return }
        garment.status = .sold
        catalogue[id] = garment
        myCart.removeAll { $0 == id }
        broadcast(.garmentSold(id: id, title: garment.title, byCurrentUser: false))
    }

    /// Fait avancer la livraison de mes commandes.
    private func advanceOrders() {
        for index in myOrders.indices {
            guard let next = myOrders[index].status.next else { continue }
            myOrders[index].status = next
            myOrders[index].timeline.append(OrderStatusEvent(status: next, date: Date()))
            if next == .shipped {
                myOrders[index].trackingNumber = "8R\(Int.random(in: 100_000_000...999_999_999))FR"
            }
            broadcast(.orderUpdated(myOrders[index]))
        }
    }
}
