import SwiftUI

/// Profil : coordonnées, livraison, paiement et suivi des commandes.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmDeletion = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isSignedIn {
                    content
                } else {
                    SignInPrompt(
                        title: "Ton profil",
                        message: "Connecte-toi pour enregistrer ton adresse, acheter et suivre tes commandes."
                    )
                }
            }
            .navigationTitle("Profil")
        }
    }

    private var content: some View {
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
                    ForEach(store.profileParts) { part in
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
                    LabeledContent("Connecté avec", value: store.account?.email ?? "")
                    Button("Se déconnecter") {
                        Task { await store.signOut() }
                    }
                    Button("Supprimer mon compte", role: .destructive) {
                        confirmDeletion = true
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("Compte")
                } footer: {
                    Text("La suppression efface ton profil, ton panier et ton historique. Les factures de tes commandes sont conservées, comme l'exige la loi.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("StyleMatch 1.0")
                            .font(.footnote.weight(.semibold))
                        if Backend.isDemo {
                            Text("Mode démo : les autres acheteurs sont simulés. Des pièces deviennent HOT et certaines sont achetées en direct par d'autres personnes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Supprimer définitivement ton compte ?",
                isPresented: $confirmDeletion,
                titleVisibility: .visible
            ) {
                Button("Supprimer mon compte", role: .destructive) {
                    isDeleting = true
                    Task {
                        _ = await store.deleteAccount()
                        isDeleting = false
                    }
                }
            } message: {
                Text("Cette action est irréversible.")
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
