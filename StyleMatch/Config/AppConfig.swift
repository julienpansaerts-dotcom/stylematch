import Foundation

/// Configuration du backend.
///
/// Ces valeurs sont **publiques par nature** (clé « anon » Supabase protégée par
/// la RLS, clé « publishable » Stripe) : elles peuvent être dans l'app.
/// Le workflow TestFlight les remplit à partir des *variables* GitHub du dépôt
/// (Settings › Secrets and variables › Actions › Variables) via
/// `.github/scripts/write-app-config.sh`.
///
/// Tant que `supabaseURL` est vide, l'app tourne en **mode démo** (données simulées).
enum AppConfig {
    static let supabaseURL = ""
    static let supabaseAnonKey = ""
    static let stripePublishableKey = ""
    /// Identifiant marchand Apple Pay (ex. merchant.stylematch). Vide = carte uniquement.
    static let applePayMerchantID = ""

    static var isBackendConfigured: Bool {
        URL(string: supabaseURL) != nil && !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
