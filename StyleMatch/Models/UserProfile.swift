import Foundation

enum DeliveryMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, relayPoint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "À domicile"
        case .relayPoint: return "Point relais"
        }
    }

    var carrier: String {
        switch self {
        case .home: return "Colissimo"
        case .relayPoint: return "Mondial Relay"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .relayPoint: return "mappin.and.ellipse"
        }
    }
}

struct ShippingAddress: Codable, Equatable, Hashable, Sendable {
    var line1: String = ""
    var line2: String = ""
    var postalCode: String = ""
    var city: String = ""
    var country: String = "France"

    var isComplete: Bool {
        !line1.trimmed.isEmpty && !postalCode.trimmed.isEmpty && !city.trimmed.isEmpty && !country.trimmed.isEmpty
    }

    var singleLine: String {
        [line1, line2, "\(postalCode) \(city)", country]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct PaymentMethod: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case card, applePay, paypal

        var id: String { rawValue }

        var label: String {
            switch self {
            case .card: return "Carte"
            case .applePay: return "Apple Pay"
            case .paypal: return "PayPal"
            }
        }

        var symbol: String {
            switch self {
            case .card: return "creditcard.fill"
            case .applePay: return "apple.logo"
            case .paypal: return "p.circle.fill"
            }
        }
    }

    var kind: Kind
    var holderName: String = ""
    /// Seuls la marque et les 4 derniers chiffres sont conservés.
    var brand: String = ""
    var last4: String = ""
    var expiry: String = ""
    var paypalEmail: String = ""

    var summary: String {
        switch kind {
        case .card: return "\(brand) •••• \(last4) · exp. \(expiry)"
        case .applePay: return "Apple Pay"
        case .paypal: return "PayPal · \(paypalEmail)"
        }
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    enum Part: String, CaseIterable, Identifiable {
        case personal, address, payment
        var id: String { rawValue }

        var label: String {
            switch self {
            case .personal: return "Informations personnelles"
            case .address: return "Adresse de livraison"
            case .payment: return "Moyen de paiement"
            }
        }

        var symbol: String {
            switch self {
            case .personal: return "person.fill"
            case .address: return "house.fill"
            case .payment: return "creditcard.fill"
            }
        }
    }

    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phone: String = ""
    var address = ShippingAddress()
    var deliveryMethod: DeliveryMethod = .home
    var relayPoint: String = ""
    var payment: PaymentMethod?

    var fullName: String {
        "\(firstName.trimmed) \(lastName.trimmed)".trimmed
    }

    var initials: String {
        let letters = [firstName, lastName].compactMap { $0.trimmed.first }.map { String($0) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    var isPersonalInfoComplete: Bool {
        !firstName.trimmed.isEmpty && !lastName.trimmed.isEmpty && email.contains("@")
    }

    var isDeliveryComplete: Bool {
        address.isComplete && (deliveryMethod == .home || !relayPoint.trimmed.isEmpty)
    }

    func isComplete(_ section: Part) -> Bool {
        switch section {
        case .personal: return isPersonalInfoComplete
        case .address: return isDeliveryComplete
        case .payment: return payment != nil
        }
    }

    var missingSections: [Part] {
        Part.allCases.filter { !isComplete($0) }
    }

    var isReadyForCheckout: Bool { missingSections.isEmpty }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
