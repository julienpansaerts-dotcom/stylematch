import SwiftUI

/// Onglet « Boutique » (réservé au vendeur) : catalogue et commandes à expédier.
struct AdminView: View {
    @Environment(AppStore.self) private var store

    private enum Tab: String, CaseIterable, Identifiable {
        case pieces = "Pièces"
        case orders = "Commandes"
        var id: String { rawValue }
    }

    /// Pièce à éditer (nil = nouvelle pièce).
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let garment: Garment?
    }

    @State private var tab: Tab = .pieces
    @State private var garments: [Garment] = []
    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editor: EditorTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch tab {
                case .pieces: piecesList
                case .orders: ordersList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Boutique")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = EditorTarget(garment: nil)
                    } label: {
                        Label("Nouvelle pièce", systemImage: "plus.circle.fill")
                    }
                }
            }
            .overlay {
                if isLoading && garments.isEmpty && orders.isEmpty { ProgressView() }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(item: $editor) { target in
                GarmentEditorView(
                    draft: target.garment.map(GarmentDraft.init(garment:)) ?? GarmentDraft()
                ) { saved in
                    if let index = garments.firstIndex(where: { $0.id == saved.id }) {
                        garments[index] = saved
                    } else {
                        garments.insert(saved, at: 0)
                    }
                }
            }
        }
    }

    // MARK: - Pièces

    private var piecesList: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.pass)
            }
            Section {
                ForEach(garments) { garment in
                    Button {
                        editor = EditorTarget(garment: garment)
                    } label: {
                        AdminGarmentRow(garment: garment)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        if garment.status == .available {
                            Button("Retirer") { setWithdrawn(garment, true) }.tint(.orange)
                        } else if garment.status == .withdrawn {
                            Button("Remettre en vente") { setWithdrawn(garment, false) }.tint(Theme.like)
                        }
                    }
                }
            } header: {
                Text("\(garments.filter { $0.status == .available }.count) en vente · \(garments.filter { $0.status == .sold }.count) vendues")
            } footer: {
                Text("Glisse une pièce vers la gauche pour la retirer de la vente. Touche « + » pour publier une nouvelle pièce.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func setWithdrawn(_ garment: Garment, _ withdrawn: Bool) {
        Task {
            do {
                try await store.setGarmentWithdrawn(garment.id, withdrawn: withdrawn)
                if let index = garments.firstIndex(where: { $0.id == garment.id }) {
                    garments[index].status = withdrawn ? .withdrawn : .available
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Commandes

    private var toShip: [Order] { orders.filter { $0.status <= .preparing } }
    private var inDelivery: [Order] { orders.filter { $0.status > .preparing && $0.status < .delivered } }
    private var delivered: [Order] { orders.filter { $0.status == .delivered } }

    private var ordersList: some View {
        List {
            orderSection("À expédier", toShip)
            orderSection("En cours de livraison", inDelivery)
            orderSection("Livrées", delivered)
            if orders.isEmpty && !isLoading {
                Text("Aucune commande pour l'instant.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func orderSection(_ title: String, _ items: [Order]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { order in
                    NavigationLink {
                        AdminOrderView(order: order) { updated in
                            if let index = orders.firstIndex(where: { $0.id == updated.id }) {
                                orders[index] = updated
                            }
                        }
                    } label: {
                        OrderRow(order: order)
                    }
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalogue = store.adminCatalogue()
            async let allOrders = store.adminOrders()
            garments = try await catalogue
            orders = try await allOrders
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminGarmentRow: View {
    let garment: Garment

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(source: garment.photos.first, compact: true)
                .frame(width: 56, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(garment.status == .available ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(garment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(garment.brand) · \(garment.sizeLabel) · \(garment.formattedPrice)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    statusChip
                    if garment.cartCount > 0 {
                        Label("\(garment.cartCount)", systemImage: garment.isHot ? "flame.fill" : "bag.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(garment.isHot ? Theme.hotOrange : Color.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "pencil").foregroundStyle(.tertiary)
        }
    }

    private var statusChip: some View {
        let (label, color): (String, Color) = {
            switch garment.status {
            case .available: return ("En vente", Theme.like)
            case .sold: return ("Vendue", Theme.buy)
            case .withdrawn: return ("Retirée", .orange)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Détail d'une commande côté boutique : destinataire, contenu, expédition.
private struct AdminOrderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let order: Order
    let onUpdate: (Order) -> Void

    @State private var status: OrderStatus
    @State private var trackingNumber: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(order: Order, onUpdate: @escaping (Order) -> Void) {
        self.order = order
        self.onUpdate = onUpdate
        _status = State(initialValue: order.status)
        _trackingNumber = State(initialValue: order.trackingNumber ?? "")
    }

    var body: some View {
        Form {
            Section("Destinataire") {
                Text(order.buyerName.isEmpty ? "—" : order.buyerName).font(.headline)
                Label(order.deliveryMethod.label, systemImage: order.deliveryMethod.symbol)
                if order.deliveryMethod == .relayPoint && !order.relayPoint.isEmpty {
                    Text(order.relayPoint)
                }
                Text(order.shippingAddress.singleLine)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Pièces à emballer") {
                ForEach(order.items) { garment in
                    HStack {
                        PhotoView(source: garment.photos.first, compact: true)
                            .frame(width: 40, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(garment.title).font(.subheadline.weight(.semibold))
                            Text("\(garment.brand) · \(garment.sizeLabel)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Picker("Statut", selection: $status) {
                    ForEach(OrderStatus.allCases, id: \.self) { status in
                        Text(status.label(for: order.deliveryMethod)).tag(status)
                    }
                }
                TextField("N° de suivi \(order.carrier)", text: $trackingNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Expédition")
            } footer: {
                Text("Le client est prévenu en direct dans l'app à chaque changement.")
            }

            Section("Montant") {
                LabeledContent("Total payé", value: Money.format(order.totalCents))
                LabeledContent("Dont livraison", value: Money.format(order.shippingCents))
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.pass)
            }
        }
        .navigationTitle(order.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", action: save)
                    .disabled(isSaving || (status == order.status && trackingNumber == (order.trackingNumber ?? "")))
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                let tracking = trackingNumber.trimmed
                let updated = try await store.updateOrder(order.id, status: status, trackingNumber: tracking.isEmpty ? nil : tracking)
                onUpdate(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
