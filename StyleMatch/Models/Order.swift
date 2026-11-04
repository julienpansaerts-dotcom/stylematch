import Foundation

enum OrderStatus: Int, CaseIterable, Comparable, Codable, Sendable {
    case confirmed, preparing, shipped, inTransit, outForDelivery, delivered

    static func < (lhs: OrderStatus, rhs: OrderStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    func label(for method: DeliveryMethod) -> String {
        switch self {
        case .confirmed: return "Commande confirmée"
        case .preparing: return "Colis en préparation"
        case .shipped: return "Expédiée"
        case .inTransit: return "En transit"
        case .outForDelivery: return method == .home ? "En cours de livraison" : "Disponible au point relais"
        case .delivered: return method == .home ? "Livrée" : "Récupérée"
        }
    }

    var symbol: String {
        switch self {
        case .confirmed: return "checkmark.seal.fill"
        case .preparing: return "shippingbox.fill"
        case .shipped: return "paperplane.fill"
        case .inTransit: return "arrow.triangle.swap"
        case .outForDelivery: return "figure.walk"
        case .delivered: return "house.fill"
        }
    }

    var next: OrderStatus? { OrderStatus(rawValue: rawValue + 1) }
}

struct OrderStatusEvent: Hashable, Sendable {
    let status: OrderStatus
    let date: Date
}

struct Order: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let createdAt: Date
    var items: [Garment]
    let subtotalCents: Int
    let shippingCents: Int
    let serviceFeeCents: Int
    let deliveryMethod: DeliveryMethod
    let shippingAddress: ShippingAddress
    let relayPoint: String
    let paymentSummary: String
    var trackingNumber: String?
    var status: OrderStatus
    var timeline: [OrderStatusEvent]

    var totalCents: Int { subtotalCents + shippingCents + serviceFeeCents }
    var carrier: String { deliveryMethod.carrier }
    var statusLabel: String { status.label(for: deliveryMethod) }
    var isActive: Bool { status != .delivered }

    var estimatedDelivery: Date {
        Calendar.current.date(byAdding: .day, value: 3, to: createdAt) ?? createdAt
    }

    func date(of status: OrderStatus) -> Date? {
        timeline.first { $0.status == status }?.date
    }
}
