import Foundation
import Supabase

/// Vrai backend : Supabase (base, temps réel, photos, fonctions) + Stripe.
/// Voir `supabase/migrations` et `supabase/functions`.
final class SupabaseMarketplaceService: MarketplaceService, @unchecked Sendable {
    let usesExternalPaymentSheet = true

    private let client: SupabaseClient
    private let photosBucket = "garment-photos"
    private let decoder = PostgrestClient.Configuration.jsonDecoder

    init(client: SupabaseClient) {
        self.client = client
    }

    private func userID() throws -> String {
        guard let user = client.auth.currentUser else { throw MarketplaceError.notSignedIn }
        return user.id.uuidString.lowercased()
    }

    // MARK: - Catalogue & swipe

    func feed(filters: FeedFilters, excluding: Set<String>, limit: Int) async throws -> [Garment] {
        let params = FeedParams(
            p_limit: limit,
            p_exclude: Array(excluding),
            p_genders: filters.genders.map(\.rawValue),
            p_categories: filters.categories.map(\.rawValue),
            p_sizes: Array(filters.sizes),
            p_conditions: filters.conditions.map(\.rawValue),
            p_colors: filters.colors.map(\.rawValue),
            p_min_cents: filters.minPrice * 100,
            p_max_cents: filters.maxPrice < FeedFilters.priceCeiling ? filters.maxPrice * 100 : nil,
            p_hot_only: filters.hotOnly,
            p_hot_threshold: Garment.hotThreshold
        )
        let rows: [GarmentRow] = try await call { try await self.client.rpc("feed", params: params).execute().value }
        return rows.map(\.garment)
    }

    func garments(ids: [String]) async throws -> [Garment] {
        guard !ids.isEmpty else { return [] }
        let rows: [GarmentRow] = try await call {
            try await self.client.from("garments").select().in("id", values: ids).execute().value
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.garment) })
        return ids.compactMap { byID[$0] }
    }

    func swipeHistory() async throws -> SwipeHistory {
        guard client.auth.currentUser != nil else { return SwipeHistory() }
        let rows: [SwipeRow] = try await call {
            try await self.client.from("swipes").select("garment_id, direction")
                .order("created_at", ascending: true).execute().value
        }
        return SwipeHistory(
            passed: rows.filter { $0.direction == "left" }.map(\.garment_id),
            liked: Set(rows.filter { $0.direction != "left" }.map(\.garment_id))
        )
    }

    func recordSwipe(_ garmentID: String, direction: SwipeDirection) async throws {
        let row = SwipeInsert(user_id: try userID(), garment_id: garmentID, direction: direction.serverValue)
        try await call {
            try await self.client.from("swipes")
                .upsert(row, onConflict: "user_id,garment_id", returning: .minimal).execute()
        }
    }

    func forgetSwipes(_ garmentIDs: [String]) async throws {
        guard !garmentIDs.isEmpty else { return }
        let uid = try userID()
        try await call {
            try await self.client.from("swipes").delete(returning: .minimal)
                .eq("user_id", value: uid).in("garment_id", values: garmentIDs).execute()
        }
    }

    // MARK: - Panier

    func cart() async throws -> [Garment] {
        guard client.auth.currentUser != nil else { return [] }
        let rows: [DBCartRow] = try await call {
            try await self.client.from("cart_items").select("garment:garments(*)")
                .order("added_at", ascending: false).execute().value
        }
        return rows.compactMap { $0.garment?.garment }
    }

    func addToCart(_ garmentID: String) async throws -> Garment {
        let row = CartInsert(user_id: try userID(), garment_id: garmentID)
        do {
            try await client.from("cart_items")
                .upsert(row, onConflict: "user_id,garment_id", returning: .minimal, ignoreDuplicates: true)
                .execute()
        } catch let error as PostgrestError where error.code == "42501" {
            // Refusé par la RLS : la pièce n'est plus en vente.
            throw MarketplaceError.alreadySold
        } catch {
            throw map(error)
        }
        guard let garment = try await garments(ids: [garmentID]).first else { throw MarketplaceError.notFound }
        return garment
    }

    func removeFromCart(_ garmentID: String) async throws {
        let uid = try userID()
        try await call {
            try await self.client.from("cart_items").delete(returning: .minimal)
                .eq("user_id", value: uid).eq("garment_id", value: garmentID).execute()
        }
    }

    // MARK: - Paiement

    func quote(_ garmentIDs: [String]) async throws -> PriceQuote {
        let row: QuoteRow = try await call {
            try await self.client.rpc("quote_garments", params: ["p_garment_ids": garmentIDs]).execute().value
        }
        return PriceQuote(
            subtotalCents: row.subtotal_cents,
            shippingCents: [.home: row.shipping_cents.home, .relayPoint: row.shipping_cents.relayPoint],
            serviceFeeCents: row.service_fee_cents,
            unavailableIDs: Set(row.unavailable)
        )
    }

    func preparePayment(_ garmentIDs: [String], details: CheckoutDetails) async throws -> PaymentPreparation {
        _ = try userID()
        let body = CreatePaymentBody(garment_ids: garmentIDs, delivery_method: details.deliveryMethod.rawValue)
        let response: CreatePaymentResponse = try await invokeFunction("create-payment", body: body)
        let unavailable = try await garments(ids: response.unavailable)
        return PaymentPreparation(
            paymentIntentID: response.payment_intent_id,
            clientSecret: response.client_secret,
            reservedIDs: response.reserved,
            unavailable: unavailable,
            totalCents: response.total_cents
        )
    }

    func completePayment(_ preparation: PaymentPreparation, details: CheckoutDetails) async throws -> PurchaseResult {
        guard let paymentIntentID = preparation.paymentIntentID else {
            return PurchaseResult(order: nil, unavailable: preparation.unavailable)
        }
        // La commande est créée par le webhook Stripe : on l'attend quelques secondes.
        for _ in 0..<30 {
            let rows: [DBOrderRow] = try await call {
                try await self.client.from("orders").select(DBOrderRow.columns)
                    .eq("stripe_payment_intent", value: paymentIntentID).execute().value
            }
            if let order = rows.first?.order {
                let boughtIDs = Set(order.items.map(\.id))
                let lostIDs = preparation.reservedIDs.filter { !boughtIDs.contains($0) }
                let lost = try await garments(ids: lostIDs)
                return PurchaseResult(order: order, unavailable: preparation.unavailable + lost)
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw MarketplaceError.paymentPending
    }

    func cancelPayment(_ preparation: PaymentPreparation) async {
        guard let paymentIntentID = preparation.paymentIntentID else { return }
        _ = try? await client.rpc("cancel_my_payment", params: ["p_payment_intent": paymentIntentID]).execute()
    }

    // MARK: - Compte

    func orders() async throws -> [Order] {
        guard let user = client.auth.currentUser else { return [] }
        let rows: [DBOrderRow] = try await call {
            try await self.client.from("orders").select(DBOrderRow.columns)
                .eq("buyer_id", value: user.id.uuidString.lowercased())
                .order("created_at", ascending: false).execute().value
        }
        return rows.map(\.order)
    }

    func loadProfile() async throws -> UserProfile? {
        guard client.auth.currentUser != nil else { return nil }
        let rows: [ProfileRow] = try await call {
            try await self.client.from("profiles").select().eq("id", value: try self.userID()).execute().value
        }
        return rows.first?.profile
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let uid = try userID()
        try await call {
            try await self.client.from("profiles").update(ProfileUpdate(profile), returning: .minimal)
                .eq("id", value: uid).execute()
        }
    }

    // MARK: - Temps réel

    func events() async -> AsyncStream<MarketplaceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: MarketplaceEvent.self)
        let channel = client.channel("stylematch-live-\(UUID().uuidString)")
        let garmentChanges = channel.postgresChange(UpdateAction.self, schema: "public", table: "garments")
        let orderChanges = channel.postgresChange(UpdateAction.self, schema: "public", table: "orders")

        let garmentTask = Task { [decoder] in
            for await change in garmentChanges {
                guard let row = try? change.decodeRecord(as: GarmentRow.self, decoder: decoder) else { continue }
                let old = try? change.decodeOldRecord(as: PartialGarmentRow.self, decoder: decoder)
                if row.status == "sold" || row.status == "withdrawn" {
                    if old?.status != row.status {
                        continuation.yield(.garmentSold(id: row.id, title: row.title, byCurrentUser: false))
                    }
                } else {
                    continuation.yield(.cartCountChanged(id: row.id, count: row.cart_count))
                }
            }
        }
        let orderTask = Task { [weak self] in
            for await change in orderChanges {
                guard let self,
                      let row = try? change.decodeRecord(as: PartialOrderRow.self, decoder: self.decoder),
                      let order = try? await self.order(id: row.id) else { continue }
                continuation.yield(.orderUpdated(order))
            }
        }
        continuation.onTermination = { [client] _ in
            garmentTask.cancel()
            orderTask.cancel()
            Task { await client.removeChannel(channel) }
        }
        Task { try? await channel.subscribeWithError() }
        return stream
    }

    private func order(id: String) async throws -> Order? {
        let rows: [DBOrderRow] = try await client.from("orders").select(DBOrderRow.columns)
            .eq("id", value: id).execute().value
        return rows.first?.order
    }

    // MARK: - Boutique

    func adminCatalogue() async throws -> [Garment] {
        let rows: [GarmentRow] = try await call {
            try await self.client.from("garments").select().order("created_at", ascending: false).execute().value
        }
        return rows.map(\.garment)
    }

    func saveGarment(_ draft: GarmentDraft) async throws -> Garment {
        guard let priceCents = draft.priceCents else { throw MarketplaceError.server("Prix invalide.") }
        var photoURLs = draft.existingPhotos.map(\.absoluteString)
        let folder = draft.id ?? UUID().uuidString.lowercased()
        for data in draft.newPhotos {
            let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
            try await call {
                _ = try await self.client.storage.from(self.photosBucket)
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            }
            let url = try client.storage.from(photosBucket).getPublicURL(path: path)
            photoURLs.append(url.absoluteString)
        }

        let fields = GarmentWrite(draft: draft, priceCents: priceCents, photos: photoURLs)
        let row: GarmentRow
        if let id = draft.id {
            row = try await call {
                try await self.client.from("garments").update(fields).eq("id", value: id)
                    .select().single().execute().value
            }
        } else {
            row = try await call {
                try await self.client.from("garments").insert(fields.with(id: folder))
                    .select().single().execute().value
            }
        }
        return row.garment
    }

    func setGarmentWithdrawn(_ garmentID: String, withdrawn: Bool) async throws {
        try await call {
            try await self.client.from("garments")
                .update(["status": withdrawn ? "withdrawn" : "available"], returning: .minimal)
                .eq("id", value: garmentID).neq("status", value: "sold").execute()
        }
    }

    func adminOrders() async throws -> [Order] {
        let rows: [DBOrderRow] = try await call {
            try await self.client.from("orders").select(DBOrderRow.columns)
                .order("created_at", ascending: false).execute().value
        }
        return rows.map(\.order)
    }

    func updateOrder(_ orderID: String, status: OrderStatus, trackingNumber: String?) async throws -> Order {
        let update = OrderUpdate(status: status.serverValue, tracking_number: trackingNumber?.trimmed.nilIfEmpty)
        try await call {
            try await self.client.from("orders").update(update, returning: .minimal).eq("id", value: orderID).execute()
        }
        guard let order = try await order(id: orderID) else { throw MarketplaceError.notFound }
        return order
    }

    // MARK: - Utilitaires

    private func invokeFunction<Response: Decodable>(_ name: String, body: some Encodable) async throws -> Response {
        do {
            return try await client.functions.invoke(name, options: FunctionInvokeOptions(body: body))
        } catch FunctionsError.httpError(_, let data) {
            let message = (try? JSONDecoder().decode(FunctionErrorBody.self, from: data))?.error
            throw MarketplaceError.server(message ?? "Le paiement n'a pas pu être préparé.")
        } catch {
            throw map(error)
        }
    }

    @discardableResult
    private func call<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> Error {
        if error is MarketplaceError || error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code != .cancelled { return MarketplaceError.network }
        if let postgrest = error as? PostgrestError {
            return postgrest.code == "42501" ? MarketplaceError.notAllowed : MarketplaceError.server(postgrest.message)
        }
        return error
    }
}

// MARK: - Lignes de la base

private struct FeedParams: Encodable {
    let p_limit: Int
    let p_exclude: [String]
    let p_genders: [String]
    let p_categories: [String]
    let p_sizes: [String]
    let p_conditions: [String]
    let p_colors: [String]
    let p_min_cents: Int
    let p_max_cents: Int?
    let p_hot_only: Bool
    let p_hot_threshold: Int
}

struct GarmentRow: Codable, Sendable {
    let id: String
    let title: String
    let brand: String
    let summary: String
    let details: String
    let measurements: String?
    let size: String
    let gender: String
    let category: String
    let condition: String
    let color: String
    let price_cents: Int
    let photos: [String]
    let status: String
    let cart_count: Int

    var garment: Garment {
        Garment(
            id: id,
            title: title,
            brand: brand,
            summary: summary,
            details: details,
            measurements: measurements,
            size: size,
            gender: Gender(rawValue: gender) ?? .unisex,
            category: GarmentCategory(rawValue: category) ?? .accessories,
            condition: GarmentCondition(rawValue: condition) ?? .good,
            color: GarmentColor(rawValue: color) ?? .multicolor,
            priceCents: price_cents,
            photos: photos.compactMap(URL.init(string:)).map { .remote($0) },
            cartCount: cart_count,
            status: {
                switch status {
                case "sold": return .sold
                case "withdrawn": return .withdrawn
                default: return .available // « reserved » : en cours de paiement par quelqu'un
                }
            }()
        )
    }
}

private struct PartialGarmentRow: Decodable {
    let status: String?
}

private struct GarmentWrite: Encodable {
    var id: String?
    let title: String
    let brand: String
    let summary: String
    let details: String
    let measurements: String?
    let size: String
    let gender: String
    let category: String
    let condition: String
    let color: String
    let price_cents: Int
    let photos: [String]

    init(draft: GarmentDraft, priceCents: Int, photos: [String]) {
        title = draft.title.trimmed
        brand = draft.brand.trimmed
        summary = draft.summary.trimmed
        details = draft.details.trimmed
        measurements = draft.measurements.trimmed.nilIfEmpty
        size = draft.size
        gender = draft.gender.rawValue
        category = draft.category.rawValue
        condition = draft.condition.rawValue
        color = draft.color.rawValue
        price_cents = priceCents
        self.photos = photos
    }

    func with(id: String) -> GarmentWrite {
        var copy = self
        copy.id = id
        return copy
    }
}

private struct SwipeRow: Decodable {
    let garment_id: String
    let direction: String
}

private struct SwipeInsert: Encodable {
    let user_id: String
    let garment_id: String
    let direction: String
}

private struct DBCartRow: Decodable {
    let garment: GarmentRow?
}

private struct CartInsert: Encodable {
    let user_id: String
    let garment_id: String
}

private struct QuoteRow: Decodable {
    struct Shipping: Decodable {
        let home: Int
        let relayPoint: Int
    }
    let subtotal_cents: Int
    let shipping_cents: Shipping
    let service_fee_cents: Int
    let unavailable: [String]
}

private struct CreatePaymentBody: Encodable {
    let garment_ids: [String]
    let delivery_method: String
}

private struct CreatePaymentResponse: Decodable {
    let payment_intent_id: String?
    let client_secret: String?
    let reserved: [String]
    let unavailable: [String]
    let total_cents: Int
}

private struct FunctionErrorBody: Decodable {
    let error: String
}

private struct ProfileRow: Decodable {
    let first_name: String
    let last_name: String
    let email: String
    let phone: String
    let address_line1: String
    let address_line2: String
    let postal_code: String
    let city: String
    let country: String
    let delivery_method: String
    let relay_point: String

    var profile: UserProfile {
        var profile = UserProfile()
        profile.firstName = first_name
        profile.lastName = last_name
        profile.email = email
        profile.phone = phone
        profile.address = ShippingAddress(
            line1: address_line1, line2: address_line2, postalCode: postal_code, city: city, country: country
        )
        profile.deliveryMethod = DeliveryMethod(rawValue: delivery_method) ?? .home
        profile.relayPoint = relay_point
        return profile
    }
}

private struct ProfileUpdate: Encodable {
    let first_name: String
    let last_name: String
    let phone: String
    let address_line1: String
    let address_line2: String
    let postal_code: String
    let city: String
    let country: String
    let delivery_method: String
    let relay_point: String

    init(_ profile: UserProfile) {
        first_name = profile.firstName.trimmed
        last_name = profile.lastName.trimmed
        phone = profile.phone.trimmed
        address_line1 = profile.address.line1.trimmed
        address_line2 = profile.address.line2.trimmed
        postal_code = profile.address.postalCode.trimmed
        city = profile.address.city.trimmed
        country = profile.address.country
        delivery_method = profile.deliveryMethod.rawValue
        relay_point = profile.relayPoint.trimmed
    }
}

private struct PartialOrderRow: Decodable {
    let id: String
}

private struct OrderUpdate: Encodable {
    let status: String
    let tracking_number: String?
}

private struct DBOrderRow: Decodable {
    static let columns = "*, order_items(price_cents, garment:garments(*)), order_events(status, created_at)"

    struct Item: Decodable {
        let price_cents: Int
        let garment: GarmentRow?
    }

    struct Event: Decodable {
        let status: String
        let created_at: Date
    }

    struct Address: Decodable {
        let line1: String?
        let line2: String?
        let postal_code: String?
        let city: String?
        let country: String?
    }

    let id: String
    let number: String
    let created_at: Date
    let subtotal_cents: Int
    let shipping_cents: Int
    let service_fee_cents: Int
    let delivery_method: String
    let shipping_address: Address
    let relay_point: String
    let payment_summary: String
    let buyer_name: String
    let tracking_number: String?
    let status: String
    let order_items: [Item]
    let order_events: [Event]

    var order: Order {
        let timeline = order_events
            .compactMap { event in OrderStatus(serverValue: event.status).map { OrderStatusEvent(status: $0, date: event.created_at) } }
            .sorted { $0.date < $1.date }
        return Order(
            id: id,
            number: number,
            createdAt: created_at,
            items: order_items.compactMap { $0.garment?.garment },
            subtotalCents: subtotal_cents,
            shippingCents: shipping_cents,
            serviceFeeCents: service_fee_cents,
            deliveryMethod: DeliveryMethod(rawValue: delivery_method) ?? .home,
            shippingAddress: ShippingAddress(
                line1: shipping_address.line1 ?? "",
                line2: shipping_address.line2 ?? "",
                postalCode: shipping_address.postal_code ?? "",
                city: shipping_address.city ?? "",
                country: shipping_address.country ?? ""
            ),
            relayPoint: relay_point,
            paymentSummary: payment_summary,
            trackingNumber: tracking_number,
            status: OrderStatus(serverValue: status) ?? .confirmed,
            timeline: timeline,
            buyerName: buyer_name
        )
    }
}

// MARK: - Correspondances avec les énumérations SQL

extension SwipeDirection {
    var serverValue: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        }
    }
}

extension OrderStatus {
    var serverValue: String {
        switch self {
        case .confirmed: return "confirmed"
        case .preparing: return "preparing"
        case .shipped: return "shipped"
        case .inTransit: return "inTransit"
        case .outForDelivery: return "outForDelivery"
        case .delivered: return "delivered"
        }
    }

    init?(serverValue: String) {
        guard let match = OrderStatus.allCases.first(where: { $0.serverValue == serverValue }) else { return nil }
        self = match
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
