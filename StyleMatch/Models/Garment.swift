import SwiftUI

// MARK: - Genre

enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case women, men, unisex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .women: return "Femme"
        case .men: return "Homme"
        case .unisex: return "Unisexe"
        }
    }
}

// MARK: - Catégorie

enum GarmentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tshirts, shirts, knitwear, sweatshirts, jackets, coats
    case jeans, trousers, shorts, dresses, skirts
    case shoes, bags, accessories

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tshirts: return "T-shirts & tops"
        case .shirts: return "Chemises"
        case .knitwear: return "Pulls & gilets"
        case .sweatshirts: return "Sweats & hoodies"
        case .jackets: return "Vestes"
        case .coats: return "Manteaux"
        case .jeans: return "Jeans"
        case .trousers: return "Pantalons"
        case .shorts: return "Shorts"
        case .dresses: return "Robes"
        case .skirts: return "Jupes"
        case .shoes: return "Chaussures"
        case .bags: return "Sacs"
        case .accessories: return "Accessoires"
        }
    }

    var symbol: String {
        switch self {
        case .tshirts, .shirts, .knitwear, .sweatshirts: return "tshirt.fill"
        case .jackets, .coats, .jeans, .trousers, .shorts, .skirts: return "hanger"
        case .dresses: return "figure.dress.line.vertical.figure"
        case .shoes: return "shoe.fill"
        case .bags: return "handbag.fill"
        case .accessories: return "eyeglasses"
        }
    }
}

// MARK: - État

enum GarmentCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case newWithTags, newWithoutTags, veryGood, good, fair

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newWithTags: return "Neuf avec étiquette"
        case .newWithoutTags: return "Neuf sans étiquette"
        case .veryGood: return "Très bon état"
        case .good: return "Bon état"
        case .fair: return "Satisfaisant"
        }
    }

    var shortLabel: String {
        switch self {
        case .newWithTags, .newWithoutTags: return "Neuf"
        case .veryGood: return "Très bon"
        case .good: return "Bon"
        case .fair: return "Correct"
        }
    }
}

// MARK: - Couleur

enum GarmentColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, white, grey, beige, brown, blue, navy, green, red, pink, yellow, orange, purple, multicolor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return "Noir"
        case .white: return "Blanc"
        case .grey: return "Gris"
        case .beige: return "Beige"
        case .brown: return "Marron"
        case .blue: return "Bleu"
        case .navy: return "Marine"
        case .green: return "Vert"
        case .red: return "Rouge"
        case .pink: return "Rose"
        case .yellow: return "Jaune"
        case .orange: return "Orange"
        case .purple: return "Violet"
        case .multicolor: return "Multicolore"
        }
    }

    private var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .black: return (0.16, 0.16, 0.18)
        case .white: return (0.95, 0.94, 0.92)
        case .grey: return (0.55, 0.56, 0.58)
        case .beige: return (0.86, 0.78, 0.64)
        case .brown: return (0.52, 0.34, 0.22)
        case .blue: return (0.29, 0.50, 0.80)
        case .navy: return (0.13, 0.20, 0.40)
        case .green: return (0.27, 0.52, 0.36)
        case .red: return (0.80, 0.18, 0.20)
        case .pink: return (0.95, 0.56, 0.68)
        case .yellow: return (0.98, 0.83, 0.28)
        case .orange: return (0.96, 0.52, 0.18)
        case .purple: return (0.52, 0.34, 0.72)
        case .multicolor: return (0.90, 0.45, 0.50)
        }
    }

    /// Couleur de la pastille dans les filtres.
    var swatch: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }

    /// Dégradé utilisé pour les photos de démonstration.
    var gradient: [Color] {
        if self == .multicolor {
            return [Color(red: 0.98, green: 0.62, blue: 0.30), Color(red: 0.90, green: 0.33, blue: 0.55), Color(red: 0.35, green: 0.45, blue: 0.85)]
        }
        let c = rgb
        return [
            Color(red: min(1, c.r + 0.18), green: min(1, c.g + 0.18), blue: min(1, c.b + 0.18)),
            Color(red: c.r * 0.72, green: c.g * 0.72, blue: c.b * 0.72)
        ]
    }

    var isLight: Bool {
        switch self {
        case .white, .beige, .yellow: return true
        default: return false
        }
    }
}

// MARK: - Tailles

enum SizeCatalog {
    static let clothing = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    static let waist = ["W26", "W28", "W30", "W32", "W34", "W36"]
    static let shoes = (35...46).map { String($0) }
    static let oneSize = "TU"
}

// MARK: - Photos

enum PhotoSource: Hashable, Sendable {
    /// Photo hébergée (backend réel).
    case remote(URL)
    /// Visuel généré localement pour le mode démo.
    case placeholder(symbol: String, tint: GarmentColor, caption: String, variant: Int)
}

// MARK: - Vêtement

enum GarmentStatus: String, Codable, Sendable {
    case available, sold
}

struct Garment: Identifiable, Hashable, Sendable {
    /// Nombre de personnes à partir duquel la pièce est considérée « HOT ».
    static let hotThreshold = 8

    let id: String
    var title: String
    var brand: String
    /// Court descriptif affiché sur la carte.
    var summary: String
    /// Description complète affichée dans la fiche.
    var details: String
    var measurements: String?
    var size: String
    var gender: Gender
    var category: GarmentCategory
    var condition: GarmentCondition
    var color: GarmentColor
    var priceCents: Int
    var photos: [PhotoSource]
    /// Nombre d'utilisateurs ayant ce vêtement dans leur panier.
    var cartCount: Int
    var status: GarmentStatus

    var isHot: Bool { cartCount >= Garment.hotThreshold }
    var isAvailable: Bool { status == .available }

    var sizeLabel: String {
        size == SizeCatalog.oneSize ? "Taille unique" : "Taille \(size)"
    }

    var formattedPrice: String { Money.format(priceCents) }

    var cartCountLabel: String {
        switch cartCount {
        case 0: return "Personne ne l'a encore dans son panier"
        case 1: return "1 personne l'a dans son panier"
        default: return "\(cartCount) personnes l'ont dans leur panier"
        }
    }

    /// Nombre d'autres acheteurs intéressés quand la pièce est déjà dans mon panier.
    var otherInterestedCount: Int { max(0, cartCount - 1) }
}
