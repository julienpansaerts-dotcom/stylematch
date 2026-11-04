import SwiftUI

// MARK: - Informations personnelles

struct PersonalInfoFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = UserProfile()
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Prénom", text: $draft.firstName)
                    .textContentType(.givenName)
                TextField("Nom", text: $draft.lastName)
                    .textContentType(.familyName)
            }
            Section {
                TextField("E-mail", text: $draft.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Téléphone", text: $draft.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            } footer: {
                Text("Le téléphone permet au transporteur de te contacter.")
            }
        }
        .navigationTitle("Informations personnelles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    store.updateProfile(mergedProfile)
                    dismiss()
                }
                .disabled(!draft.isPersonalInfoComplete)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = store.profile
            loaded = true
        }
    }

    private var mergedProfile: UserProfile {
        var profile = store.profile
        profile.firstName = draft.firstName.trimmed
        profile.lastName = draft.lastName.trimmed
        profile.email = draft.email.trimmed
        profile.phone = draft.phone.trimmed
        return profile
    }
}

// MARK: - Adresse & mode de livraison

struct AddressFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ShippingAddress()
    @State private var method: DeliveryMethod = .home
    @State private var relayPoint = ""
    @State private var loaded = false

    private let countries = ["France", "Belgique", "Suisse", "Luxembourg", "Monaco"]

    var body: some View {
        Form {
            Section("Mode de livraison") {
                Picker("Mode", selection: $method) {
                    ForEach(DeliveryMethod.allCases) { method in
                        Label(method.label, systemImage: method.symbol).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Transporteur", value: method.carrier)
                LabeledContent("Frais", value: Money.format(Pricing.shipping(for: method)))
            }

            if method == .relayPoint {
                Section {
                    TextField("Ex. Tabac Le Balto – 75011 Paris", text: $relayPoint)
                } header: {
                    Text("Point relais")
                } footer: {
                    Text("Dans la version connectée, une carte des points relais proches s'affichera ici.")
                }
            }

            Section(method == .home ? "Adresse de livraison" : "Adresse de facturation") {
                TextField("Adresse", text: $address.line1)
                    .textContentType(.streetAddressLine1)
                TextField("Complément (bâtiment, étage…)", text: $address.line2)
                    .textContentType(.streetAddressLine2)
                TextField("Code postal", text: $address.postalCode)
                    .textContentType(.postalCode)
                    .keyboardType(.numberPad)
                TextField("Ville", text: $address.city)
                    .textContentType(.addressCity)
                Picker("Pays", selection: $address.country) {
                    ForEach(countries, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .navigationTitle("Livraison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    var profile = store.profile
                    profile.address = address
                    profile.deliveryMethod = method
                    profile.relayPoint = relayPoint.trimmed
                    store.updateProfile(profile)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            guard !loaded else { return }
            address = store.profile.address
            method = store.profile.deliveryMethod
            relayPoint = store.profile.relayPoint
            loaded = true
        }
    }

    private var isValid: Bool {
        address.isComplete && (method == .home || !relayPoint.trimmed.isEmpty)
    }
}

// MARK: - Paiement

struct PaymentFormView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PaymentMethod.Kind = .card
    @State private var holder = ""
    @State private var cardNumber = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var paypalEmail = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Moyen de paiement", selection: $kind) {
                    ForEach(PaymentMethod.Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch kind {
            case .card:
                cardSection
            case .applePay:
                Section {
                    Label("Le paiement sera validé avec Face ID / Touch ID au moment de l'achat.", systemImage: "apple.logo")
                }
            case .paypal:
                Section("Compte PayPal") {
                    TextField("E-mail PayPal", text: $paypalEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if let current = store.profile.payment {
                Section("Actuellement enregistré") {
                    Label(current.summary, systemImage: current.kind.symbol)
                }
            }
        }
        .navigationTitle("Paiement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", action: save)
                    .disabled(!isValid)
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let current = store.profile.payment {
                kind = current.kind
                holder = current.holderName
                paypalEmail = current.paypalEmail
            }
            if holder.isEmpty { holder = store.profile.fullName }
            loaded = true
        }
    }

    private var cardSection: some View {
        Section {
            TextField("Titulaire de la carte", text: $holder)
                .textContentType(.name)
            TextField("Numéro de carte", text: $cardNumber)
                .keyboardType(.numberPad)
                .textContentType(.creditCardNumber)
                .onChange(of: cardNumber) { _, newValue in
                    let formatted = CardValidator.format(newValue)
                    if formatted != newValue { cardNumber = formatted }
                }
            HStack {
                TextField("MM/AA", text: $expiry)
                    .keyboardType(.numberPad)
                    .onChange(of: expiry) { _, newValue in
                        let formatted = CardValidator.formatExpiry(newValue)
                        if formatted != newValue { expiry = formatted }
                    }
                SecureField("CVC", text: $cvc)
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("Carte bancaire")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !cardNumber.isEmpty && !CardValidator.isValidNumber(cardNumber) {
                    Text("Numéro de carte invalide.").foregroundStyle(Theme.pass)
                }
                Text("🔒 Seuls la marque et les 4 derniers chiffres sont conservés. En production, la saisie passe par Stripe (certifié PCI-DSS) : aucun numéro de carte ne transite par nos serveurs.")
                Text("Astuce démo : 4242 4242 4242 4242, 12/30, 123.")
            }
        }
    }

    private var isValid: Bool {
        switch kind {
        case .card:
            return !holder.trimmed.isEmpty
                && CardValidator.isValidNumber(cardNumber)
                && CardValidator.isValidExpiry(expiry)
                && (3...4).contains(cvc.filter(\.isNumber).count)
        case .applePay:
            return true
        case .paypal:
            return paypalEmail.contains("@")
        }
    }

    private func save() {
        var payment = PaymentMethod(kind: kind)
        switch kind {
        case .card:
            let digits = cardNumber.filter(\.isNumber)
            payment.holderName = holder.trimmed
            payment.brand = CardValidator.brand(for: digits)
            payment.last4 = String(digits.suffix(4))
            payment.expiry = expiry
        case .applePay:
            break
        case .paypal:
            payment.paypalEmail = paypalEmail.trimmed
        }
        var profile = store.profile
        profile.payment = payment
        store.updateProfile(profile)
        dismiss()
    }
}

// MARK: - Validation carte

enum CardValidator {
    static func format(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(19))
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && index % 4 == 0 { result.append(" ") }
            result.append(character)
        }
        return result
    }

    static func formatExpiry(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(4))
        guard digits.count > 2 else { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }

    /// Algorithme de Luhn.
    static func isValidNumber(_ input: String) -> Bool {
        let digits = input.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    static func isValidExpiry(_ input: String) -> Bool {
        let parts = input.split(separator: "/")
        guard parts.count == 2, let month = Int(parts[0]), let year = Int(parts[1]),
              (1...12).contains(month), parts[1].count == 2 else { return false }
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let currentYear = (now.year ?? 2000) % 100
        let currentMonth = now.month ?? 1
        return year > currentYear || (year == currentYear && month >= currentMonth)
    }

    static func brand(for digits: String) -> String {
        if digits.hasPrefix("4") { return "Visa" }
        if digits.hasPrefix("34") || digits.hasPrefix("37") { return "Amex" }
        if let prefix2 = Int(digits.prefix(2)), (51...55).contains(prefix2) { return "Mastercard" }
        if let prefix4 = Int(digits.prefix(4)), (2221...2720).contains(prefix4) { return "Mastercard" }
        return "Carte"
    }
}
