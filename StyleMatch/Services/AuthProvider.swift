import Foundation

/// Compte connecté.
struct Account: Equatable, Sendable {
    let id: String
    let email: String
    /// La boutique (seul vendeur) : accès à l'onglet Boutique.
    let isAdmin: Bool
}

/// Connexion des utilisateurs (Apple ou code reçu par e-mail).
protocol AuthProvider: Sendable {
    /// Émet le compte courant (nil = déconnecté) puis chaque changement.
    func accountChanges() async -> AsyncStream<Account?>
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws
    func signOut() async throws
    /// Supprime définitivement le compte (exigence App Store).
    func deleteAccount() async throws
}

/// Mode démo : toujours connecté avec un compte « boutique » pour tout essayer.
actor DemoAuthProvider: AuthProvider {
    static let demoAccount = Account(id: "demo", email: "demo@stylematch.app", isAdmin: true)

    private var account: Account? = DemoAuthProvider.demoAccount
    private var continuations: [UUID: AsyncStream<Account?>.Continuation] = [:]

    init(signedIn: Bool = true) {
        account = signedIn ? DemoAuthProvider.demoAccount : nil
    }

    func accountChanges() -> AsyncStream<Account?> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Account?.self)
        continuations[id] = continuation
        continuation.yield(account)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws {
        set(DemoAuthProvider.demoAccount)
    }

    func sendEmailCode(to email: String) async throws {}

    func verifyEmailCode(email: String, code: String) async throws {
        set(Account(id: "demo", email: email, isAdmin: true))
    }

    func signOut() async throws { set(nil) }

    func deleteAccount() async throws { set(nil) }

    private func set(_ newAccount: Account?) {
        account = newAccount
        for continuation in continuations.values { continuation.yield(newAccount) }
    }

    private func remove(_ id: UUID) { continuations[id] = nil }
}
