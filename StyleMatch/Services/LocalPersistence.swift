import Foundation
import Security

/// Sauvegarde locale des préférences de l'utilisateur.
///
/// - Le **profil** (nom, e-mail, adresse, 4 derniers chiffres de la carte) est
///   chiffré dans le **trousseau iOS** (Keychain), accessible uniquement sur cet
///   appareil après le premier déverrouillage.
/// - Les **filtres** (non sensibles) restent dans `UserDefaults`.
/// - Le panier, les commandes et l'historique des swipes viennent du serveur
///   (table `swipes` dans `backend/supabase/schema.sql`).
struct LocalPersistence {
    private enum Key: String {
        case profile = "stylematch.profile"
        case filters = "stylematch.filters"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychainService: String = "stylematch") {
        self.defaults = defaults
        self.keychain = KeychainStore(service: keychainService)
    }

    func loadProfile() -> UserProfile? {
        if let data = keychain.data(for: Key.profile.rawValue) {
            return try? JSONDecoder().decode(UserProfile.self, from: data)
        }
        // Migration : les premières versions stockaient le profil en clair.
        guard let legacy = load(UserProfile.self, .profile) else { return nil }
        saveProfile(legacy)
        defaults.removeObject(forKey: Key.profile.rawValue)
        return legacy
    }

    func saveProfile(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        keychain.set(data, for: Key.profile.rawValue)
    }

    /// Déconnexion / suppression du compte : plus aucune donnée personnelle sur l'appareil.
    func clearProfile() {
        keychain.delete(Key.profile.rawValue)
        defaults.removeObject(forKey: Key.profile.rawValue)
    }

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

/// Accès minimal au trousseau iOS (mots de passe génériques).
struct KeychainStore {
    let service: String

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func data(for account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query = baseQuery(account).merging(attributes) { _, new in new }
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    func delete(_ account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
