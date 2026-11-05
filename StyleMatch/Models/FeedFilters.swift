import Foundation

/// Critères de la pile de vêtements. Un ensemble vide = « tout ».
struct FeedFilters: Codable, Equatable, Sendable {
    static let priceCeiling = 300

    var genders: Set<Gender> = []
    var categories: Set<GarmentCategory> = []
    var sizes: Set<String> = []
    var conditions: Set<GarmentCondition> = []
    var colors: Set<GarmentColor> = []
    var minPrice: Int = 0
    var maxPrice: Int = FeedFilters.priceCeiling
    var hotOnly: Bool = false

    func matches(_ garment: Garment) -> Bool {
        if !genders.isEmpty && !genders.contains(garment.gender) { return false }
        if !categories.isEmpty && !categories.contains(garment.category) { return false }
        if !sizes.isEmpty && !sizes.contains(garment.size) { return false }
        if !conditions.isEmpty && !conditions.contains(garment.condition) { return false }
        if !colors.isEmpty && !colors.contains(garment.color) { return false }
        // Comparaison en centimes : 29,99 € ne passe pas « jusqu'à 29 € ».
        if garment.priceCents < minPrice * 100 { return false }
        if maxPrice < FeedFilters.priceCeiling && garment.priceCents > maxPrice * 100 { return false }
        if hotOnly && !garment.isHot { return false }
        return true
    }

    /// Nombre de filtres actifs (pour la pastille sur le bouton).
    var activeCount: Int {
        var count = 0
        if !genders.isEmpty { count += 1 }
        if !categories.isEmpty { count += 1 }
        if !sizes.isEmpty { count += 1 }
        if !conditions.isEmpty { count += 1 }
        if !colors.isEmpty { count += 1 }
        if minPrice > 0 || maxPrice < FeedFilters.priceCeiling { count += 1 }
        if hotOnly { count += 1 }
        return count
    }

    var priceRangeLabel: String {
        let upper = maxPrice >= FeedFilters.priceCeiling ? "\(FeedFilters.priceCeiling) € et +" : "\(maxPrice) €"
        return "De \(minPrice) € à \(upper)"
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}
