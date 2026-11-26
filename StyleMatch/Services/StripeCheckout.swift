import StripePaymentSheet
import SwiftUI
import UIKit

/// Feuille de paiement native de Stripe (carte bancaire + Apple Pay).
/// Le numéro de carte ne passe jamais par l'app ni par nos serveurs.
enum StripeCheckout {
    @MainActor
    static func makeSheet(clientSecret: String, profile: UserProfile) -> PaymentSheet {
        STPAPIClient.shared.publishableKey = AppConfig.stripePublishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "StyleMatch"
        configuration.allowsDelayedPaymentMethods = false
        if !AppConfig.applePayMerchantID.isEmpty {
            configuration.applePay = .init(merchantId: AppConfig.applePayMerchantID, merchantCountryCode: "FR")
        }
        configuration.defaultBillingDetails.name = profile.fullName
        configuration.defaultBillingDetails.email = profile.email
        configuration.primaryButtonLabel = "Payer"

        var appearance = PaymentSheet.Appearance()
        appearance.colors.primary = UIColor(Theme.accent)
        appearance.cornerRadius = 14
        configuration.appearance = appearance

        return PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
    }
}
