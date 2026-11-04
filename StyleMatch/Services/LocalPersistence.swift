import Foundation

/// Sauvegarde locale des préférences de l'utilisateur (profil, filtres).
/// Le panier, les commandes et l'historique des swipes viennent du serveur
/// (table `swipes` dans `backend/supabase/schema.sql`).
struct LocalPersistence {
    private enum Key: String {
        case profile = "stylematch.profile"
        case filters = "stylematch.filters"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadProfile() -> UserProfile? { load(UserProfile.self, .profile) }
    func saveProfile(_ profile: UserProfile) { save(profile, .profile) }

    func loadFilters() -> FeedFilters? { load(FeedFilters.self, .filters) }
    func saveFilters(_ filters: FeedFilters) { save(filters, .filters) }

    private func load<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }
}
