import SwiftUI

/// Feuille de paiement (achat express, achat d'une pièce ou de tout le panier).
struct CheckoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: CheckoutRequest

    @State private var isProcessing = false
    @State private var outcome: CheckoutOutcome?
    /// Montants calculés par le serveur (nil pendant le chargement).
    @State private var quote: PriceQuote?
    @State private var quoteError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let outcome {
                    CheckoutResultView(outcome: outcome, onClose: { dismiss() }, onRetry: { self.outcome = nil })
                } else {
                    form
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if outcome == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                            .disabled(isProcessing)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isProcessing)
    }

    private var title: String {
        switch request.origin {
        case .buyNow: return "Achat express ⚡️"
        case .cartItem: return "Paiement"
        case .wholeCart: return "Acheter tout le panier"
        }
    }

    // MARK: - Calculs

    private func isUnavailable(_ garment: Garment) -> Bool {
        store.isUnavailable(garment.id) || (quote?.unavailableIDs.contains(garment.id) ?? false)
    }

    private var availableGarments: [Garment] {
        request.garments.filter { !isUnavailable($0) }
    }

    private var method: DeliveryMethod { store.profile.deliveryMethod }

    private func amount(_ cents: Int?) -> String {
        cents.map(Money.format) ?? "…"
    }

    private func loadQuote() async {
        do {
            let newQuote = try await store.quote(for: availableGarments)
            quote = newQuote
            quoteError = nil
        } catch {
            quoteError = error.localizedDescription
        }
    }

    // MARK: - Formulaire

    private var form: some View {
        List {
            Section("Articles") {
                ForEach(request.garments) { garment in
                    CheckoutItemRow(garment: store.liveVersion(of: garment), isSold: isUnavailable(garment))
                }
            }

            if !store.profile.isReadyForCheckout {
                Section {
                    ForEach(store.profile.missingSections) { part in
                        NavigationLink {
                            ProfileFormDestination(part: part)
                        } label: {
                            Label("Compléter : \(part.label)", systemImage: part.symbol)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Label("Infos manquantes", systemImage: "exclamationmark.triangle.fill")
                } footer: {
                    Text("Ces informations seront enregistrées dans ton profil pour tes prochains achats.")
                }
            }

            Section("Livraison") {
                Picker("Mode", selection: deliveryMethod) {
                    ForEach(DeliveryMethod.allCases) { method in
                        Text("\(method.label) · \(amount(quote?.shippingCents[method]))").tag(method)
                    }
                }
                NavigationLink {
                    AddressFormView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.profile.fullName.isEmpty ? "Destinataire" : store.profile.fullName)
                            .font(.subheadline.weight(.semibold))
                        Text(deliverySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Paiement") {
                NavigationLink {
                    PaymentFormView()
                } label: {
                    if let payment = store.profile.payment {
                        Label(payment.summary, systemImage: payment.kind.symbol)
                    } else {
                        Label("Ajouter un moyen de paiement", systemImage: "creditcard")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                row("Articles (\(availableGarments.count))", quote?.subtotalCents)
                row("Livraison \(method.carrier)", quote?.shipping(for: method))
                row("Protection acheteur", quote?.serviceFeeCents)
                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(amount(quote?.total(for: method)))
                        .font(.headline)
                }
            } header: {
                Text("Récapitulatif")
            } footer: {
                if let quoteError {
                    Text("Impossible de calculer le total : \(quoteError)")
                        .foregroundStyle(Theme.pass)
                }
            }

            Section {
                Label("Pièces uniques : si une pièce est vendue juste avant ton paiement, elle est retirée de la commande et tu n'es pas débité pour elle.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            payButton
        }
        // Recalcule le devis si une pièce est vendue entre-temps.
        .task(id: availableGarments.map(\.id)) {
            await loadQuote()
        }
    }

    private var payButton: some View {
        Button(action: pay) {
            HStack(spacing: 10) {
                if isProcessing {
                    ProgressView().tint(.white)
                    Text("Paiement en cours…")
                } else {
                    Image(systemName: store.profile.payment?.kind.symbol ?? "creditcard.fill")
                    Text("Payer \(amount(quote?.total(for: method)))")
                }
            }
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(!store.profile.isReadyForCheckout || availableGarments.isEmpty || isProcessing || quote == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func row(_ label: String, _ cents: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amount(cents))
                .foregroundStyle(.secondary)
        }
    }

    private var deliverySummary: String {
        let profile = store.profile
        guard profile.address.isComplete else { return "Ajouter une adresse" }
        if profile.deliveryMethod == .relayPoint {
            return profile.relayPoint.isEmpty ? "Choisir un point relais" : profile.relayPoint
        }
        return profile.address.singleLine
    }

    private var deliveryMethod: Binding<DeliveryMethod> {
        Binding(
            get: { store.profile.deliveryMethod },
            set: { store.setDeliveryMethod($0) }
        )
    }

    private func pay() {
        isProcessing = true
        Task {
            let result = await store.confirmCheckout(request)
            isProcessing = false
            switch result {
            case .success: Haptics.success()
            case .allUnavailable: Haptics.warning()
            case .failure: Haptics.error()
            }
            withAnimation(.spring) { outcome = result }
        }
    }
}

// MARK: - Ligne article

private struct CheckoutItemRow: View {
    let garment: Garment
    let isSold: Bool

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(source: garment.photos.first, compact: true)
                .frame(width: 52, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .grayscale(isSold ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(garment.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(isSold)
                Text("\(garment.brand) · \(garment.sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSold {
                    Text("Vendue entre-temps 💔")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.pass)
                } else if garment.isHot {
                    Label("HOT — dépêche-toi !", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(garment.formattedPrice)
                .font(.subheadline.weight(.bold))
                .strikethrough(isSold)
        }
    }
}

// MARK: - Résultat

private struct CheckoutResultView: View {
    let outcome: CheckoutOutcome
    let onClose: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            switch outcome {
            case let .success(order, unavailable):
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.like)
                    .symbolEffect(.bounce, value: order.id)
                Text("Commande confirmée !")
                    .font(.title.weight(.bold))
                Text("Commande \(order.number) · \(Money.format(order.totalCents))\nSuis ta livraison dans Profil › Mes commandes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if !unavailable.isEmpty {
                    unavailableBox(unavailable)
                }

            case let .allUnavailable(items):
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.pass)
                Text("Trop tard… 💔")
                    .font(.title.weight(.bold))
                Text(items.count > 1
                     ? "Ces pièces uniques ont été achetées juste avant toi. Tu n'as pas été débité."
                     : "Cette pièce unique a été achetée juste avant toi. Tu n'as pas été débité.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

            case let .failure(message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.orange)
                Text("Paiement impossible")
                    .font(.title.weight(.bold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Réessayer", action: onRetry)
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button("Continuer", action: onClose)
                .buttonStyle(GradientButtonStyle())
        }
        .padding(24)
    }

    private func unavailableBox(_ items: [Garment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Vendues juste avant ton paiement (non débitées) :", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
            ForEach(items) { garment in
                Text("• \(garment.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.pass.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
