import Foundation

/// Backend simulé en mémoire.
///
/// Il reproduit le comportement du vrai serveur, y compris l'activité des
/// AUTRES utilisateurs : des gens ajoutent des pièces à leur panier (ce qui
/// les rend HOT) et achètent parfois une pièce qui est dans TON panier —
/// elle disparaît alors de ton panier en direct (« Trop tard ! »).
actor MockMarketplaceService: MarketplaceService {
    private var catalogue: [String: Garment]
    private var feedOrder: [String]
    private var myCart: [String] = []
    private var myOrders: [Order]
    private var subscribers: [UUID: AsyncStream<MarketplaceEvent>.Continuation] = [:]
    private var simulationTask: Task<Void, Never>?
    private let simulateOtherUsers: Bool
    private var orderCounter = 41

    init(simulateOtherUsers: Bool = true) {
        let items = MockCatalogue.makeGarments()
        self.catalogue = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.feedOrder = items.map(\.id)
        self.myOrders = MockCatalogue.makePastOrders()
        self.simulateOtherUsers = simulateOtherUsers
    }

    deinit {
        simulationTask?.cancel()
    }

    // MARK: - Lecture

    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment] {
        try await networkDelay()
        let result = feedOrder
            .compactMap { catalogue[$0] }
            .filter { $0.isAvailable && !excluding.contains($0.id) && !myCart.contains($0.id) && filters.matches($0) }
        return Array(result.prefix(limit))
    }

    func garments(ids: [String]) async throws -> [Garment] {
        try await networkDelay()
        return ids.compactMap { catalogue[$0] }
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

    func purchase(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PurchaseResult {
        // Simule l'autorisation bancaire.
        try await Task.sleep(for: .milliseconds(900))

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
            shippingCents: Pricing.shipping(for: details.deliveryMethod),
            serviceFeeCents: Pricing.serviceFee(subtotal: subtotal),
            deliveryMethod: details.deliveryMethod,
            shippingAddress: details.address,
            relayPoint: details.relayPoint,
            paymentSummary: details.payment.summary,
            trackingNumber: nil,
            status: .confirmed,
            timeline: [OrderStatusEvent(status: .confirmed, date: now)]
        )
        myOrders.insert(order, at: 0)

        for garment in bought {
            broadcast(.garmentSold(id: garment.id, title: garment.title, byCurrentUser: true))
        }
        return PurchaseResult(order: order, unavailable: unavailable)
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
        try await Task.sleep(for: .milliseconds(Int.random(in: 120...300)))
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
        if tick % 10 == 0 { simulateSomeoneElseBuying() }
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

    /// Un autre utilisateur achète une pièce — parfois une pièce de mon panier.
    private func simulateSomeoneElseBuying() {
        let target: String?
        if !myCart.isEmpty && Double.random(in: 0...1) < 0.4 {
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
