import Foundation
import Testing
@testable import StyleMatch

@Suite("Filtres")
struct FeedFiltersTests {
    private func garment(priceCents: Int, cartCount: Int = 0, category: GarmentCategory = .tshirts) -> Garment {
        Garment(
            id: UUID().uuidString, title: "Test", brand: "Marque", summary: "", details: "", measurements: nil,
            size: "M", gender: .unisex, category: category, condition: .good, color: .black,
            priceCents: priceCents, photos: [], cartCount: cartCount, status: .available
        )
    }

    @Test("Le prix max tient compte des centimes")
    func maxPriceUsesCents() {
        var filters = FeedFilters()
        filters.maxPrice = 29
        #expect(filters.matches(garment(priceCents: 2900)))
        #expect(!filters.matches(garment(priceCents: 2999)))
    }

    @Test("Le prix min tient compte des centimes")
    func minPriceUsesCents() {
        var filters = FeedFilters()
        filters.minPrice = 30
        #expect(!filters.matches(garment(priceCents: 2999)))
        #expect(filters.matches(garment(priceCents: 3000)))
    }

    @Test("Le plafond de prix signifie « sans limite »")
    func ceilingMeansNoLimit() {
        #expect(FeedFilters().matches(garment(priceCents: 99_900)))
    }

    @Test("Filtre HOT et catégories")
    func hotAndCategories() {
        var filters = FeedFilters()
        filters.hotOnly = true
        filters.categories = [.shoes]
        #expect(filters.matches(garment(priceCents: 1000, cartCount: Garment.hotThreshold, category: .shoes)))
        #expect(!filters.matches(garment(priceCents: 1000, cartCount: Garment.hotThreshold - 1, category: .shoes)))
        #expect(!filters.matches(garment(priceCents: 1000, cartCount: Garment.hotThreshold, category: .bags)))
        #expect(filters.activeCount == 2)
    }
}

@Suite("Carte bancaire")
struct CardValidatorTests {
    @Test("Algorithme de Luhn", arguments: [
        ("4242 4242 4242 4242", true),
        ("5555 5555 5555 4444", true),
        ("4242 4242 4242 4241", false),
        ("1234", false)
    ])
    func luhn(number: String, valid: Bool) {
        #expect(CardValidator.isValidNumber(number) == valid)
    }

    @Test("Mise en forme du numéro et de la date")
    func formatting() {
        #expect(CardValidator.format("4242424242424242") == "4242 4242 4242 4242")
        #expect(CardValidator.formatExpiry("1230") == "12/30")
        #expect(CardValidator.isValidExpiry("12/99"))
        #expect(!CardValidator.isValidExpiry("13/30"))
        #expect(!CardValidator.isValidExpiry("01/20"))
    }

    @Test("Détection de la marque")
    func brand() {
        #expect(CardValidator.brand(for: "4242") == "Visa")
        #expect(CardValidator.brand(for: "5555") == "Mastercard")
        #expect(CardValidator.brand(for: "3782") == "Amex")
    }
}

@Suite("Stockage local")
struct PersistenceTests {
    @Test("Le profil est relu depuis le trousseau et migré depuis l'ancien stockage")
    func profileRoundTripAndMigration() throws {
        let suite = "stylematch.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        var legacy = UserProfile()
        legacy.firstName = "Julien"
        defaults.set(try JSONEncoder().encode(legacy), forKey: "stylematch.profile")

        let persistence = LocalPersistence(defaults: defaults, keychainService: suite)
        #expect(persistence.loadProfile()?.firstName == "Julien")
        // Plus aucune donnée personnelle en clair dans UserDefaults.
        #expect(defaults.data(forKey: "stylematch.profile") == nil)
        // Toujours lisible ensuite (depuis le trousseau).
        #expect(persistence.loadProfile()?.firstName == "Julien")

        KeychainStore(service: suite).delete("stylematch.profile")
    }
}
