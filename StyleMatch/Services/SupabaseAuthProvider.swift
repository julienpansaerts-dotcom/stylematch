import Foundation
import Supabase

/// Connexion via Supabase Auth : « Se connecter avec Apple » ou code à 6 chiffres
/// reçu par e-mail (pas de mot de passe, pas de lien à ouvrir).
final class SupabaseAuthProvider: AuthProvider, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func accountChanges() async -> AsyncStream<Account?> {
        let (stream, continuation) = AsyncStream.makeStream(of: Account?.self)
        let task = Task { [client] in
            for await (_, session) in client.auth.authStateChanges {
                guard let session, !session.isExpired else {
                    continuation.yield(nil)
                    continue
                }
                let userID = session.user.id.uuidString.lowercased()
                let rows: [AdminFlag]? = try? await client.from("profiles").select("is_admin")
                    .eq("id", value: userID).execute().value
                continuation.yield(Account(
                    id: userID,
                    email: session.user.email ?? "",
                    isAdmin: rows?.first?.is_admin ?? false
                ))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        // Apple ne transmet le nom qu'à la toute première connexion : on le garde.
        let first = fullName?.givenName?.trimmed ?? ""
        let last = fullName?.familyName?.trimmed ?? ""
        if !first.isEmpty || !last.isEmpty {
            _ = try? await client.from("profiles")
                .update(["first_name": first, "last_name": last], returning: .minimal)
                .eq("id", value: session.user.id.uuidString.lowercased())
                .execute()
        }
    }

    func sendEmailCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email.trimmed.lowercased())
    }

    func verifyEmailCode(email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email.trimmed.lowercased(), token: code.trimmed, type: .email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount() async throws {
        try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(body: [String: String]()))
        try? await client.auth.signOut(scope: .local)
    }
}

private struct AdminFlag: Decodable {
    let is_admin: Bool
}

/// Choisit le backend : Supabase s'il est configuré, sinon le mode démo.
enum Backend {
    static func make() -> (service: any MarketplaceService, auth: any AuthProvider) {
        guard AppConfig.isBackendConfigured, let url = URL(string: AppConfig.supabaseURL) else {
            return (MockMarketplaceService(), DemoAuthProvider())
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey)
        return (SupabaseMarketplaceService(client: client), SupabaseAuthProvider(client: client))
    }

    static var isDemo: Bool { !AppConfig.isBackendConfigured }
}
