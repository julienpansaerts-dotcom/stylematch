import SwiftUI

/// Profil : coordonnées, livraison, paiement et suivi des commandes.
struct ProfileView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }

                Section("Mes achats") {
                    NavigationLink {
                        OrdersView()
                    } label: {
                        HStack {
                            Label("Mes commandes", systemImage: "shippingbox.fill")
                            Spacer()
                            Text("\(store.orders.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(store.orders.filter(\.isActive)) { order in
                        NavigationLink {
                            OrderDetailView(orderID: order.id)
                        } label: {
                            OrderRow(order: order)
                        }
                    }
                }

                Section {
                    ForEach(UserProfile.Part.allCases) { part in
                        NavigationLink {
                            ProfileFormDestination(part: part)
                        } label: {
                            HStack {
                                Label(part.label, systemImage: part.symbol)
                                Spacer()
                                if store.profile.isComplete(part) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.like)
                                } else {
                                    Text("À compléter")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Mon compte")
                } footer: {
                    Text("Ces informations sont utilisées pour l'achat express (swipe vers le haut).")
                }

                Section("Découverte") {
                    Button {
                        Task { await store.reviewPassed() }
                    } label: {
                        Label("Revoir les vêtements passés (\(store.passedCount))", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(store.passedCount == 0)
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("StyleMatch 1.0")
                            .font(.footnote.weight(.semibold))
                        Text("Mode démo : les autres acheteurs sont simulés. Des pièces deviennent HOT et certaines sont achetées en direct par d'autres personnes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profil")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(store.profile.initials)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Theme.brandGradient, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(store.profile.fullName.isEmpty ? "Bienvenue 👋" : store.profile.fullName)
                    .font(.title3.weight(.bold))
                Text(store.profile.email.isEmpty ? "Complète ton profil pour acheter" : store.profile.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    stat("\(store.orders.flatMap(\.items).count)", "achats")
                    stat("\(store.cart.count)", "panier")
                    stat("\(store.passedCount)", "passés")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Redirige vers le bon formulaire selon la partie du profil.
struct ProfileFormDestination: View {
    let part: UserProfile.Part

    var body: some View {
        switch part {
        case .personal: PersonalInfoFormView()
        case .address: AddressFormView()
        case .payment: PaymentFormView()
        }
    }
}
