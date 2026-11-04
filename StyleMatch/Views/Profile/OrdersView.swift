import SwiftUI

/// Liste des vêtements achetés et état de la livraison.
struct OrdersView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.orders.isEmpty {
                ContentUnavailableView(
                    "Aucune commande",
                    systemImage: "shippingbox",
                    description: Text("Swipe vers le haut sur un vêtement pour l'acheter en un geste.")
                )
            } else {
                List {
                    let active = store.orders.filter(\.isActive)
                    let delivered = store.orders.filter { !$0.isActive }
                    if !active.isEmpty {
                        Section("En cours") {
                            ForEach(active) { order in
                                NavigationLink { OrderDetailView(orderID: order.id) } label: { OrderRow(order: order) }
                            }
                        }
                    }
                    if !delivered.isEmpty {
                        Section("Terminées") {
                            ForEach(delivered) { order in
                                NavigationLink { OrderDetailView(orderID: order.id) } label: { OrderRow(order: order) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mes commandes")
    }
}

struct OrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(0..<min(order.items.count, 3), id: \.self) { index in
                    PhotoView(source: order.items[index].photos.first, compact: true)
                        .frame(width: 50, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: CGFloat(index) * 8, y: CGFloat(index) * -4)
                }
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(order.items.count > 1 ? "\(order.items.count) articles" : (order.items.first?.title ?? "Commande"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(order.number) · \(Money.format(order.totalCents))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusPill(order: order)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Détail d'une commande avec la frise de suivi de livraison.
struct OrderDetailView: View {
    @Environment(AppStore.self) private var store
    let orderID: String

    var body: some View {
        if let order = store.orders.first(where: { $0.id == orderID }) {
            content(order)
        } else {
            ContentUnavailableView("Commande introuvable", systemImage: "questionmark.folder")
        }
    }

    private func content(_ order: Order) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: order.status.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(Theme.brandGradient)
                        .symbolEffect(.bounce, value: order.status)
                    Text(order.statusLabel)
                        .font(.title2.weight(.bold))
                    if order.isActive {
                        Text("Livraison estimée : \(order.estimatedDelivery.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Suivi") {
                timeline(order)
                if let tracking = order.trackingNumber {
                    LabeledContent(order.carrier) {
                        Text(tracking)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    LabeledContent(order.carrier, value: "N° de suivi bientôt disponible")
                }
            }

            Section("Articles") {
                ForEach(order.items) { garment in
                    HStack(spacing: 12) {
                        PhotoView(source: garment.photos.first, compact: true)
                            .frame(width: 48, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(garment.title).font(.subheadline.weight(.semibold))
                            Text("\(garment.brand) · \(garment.sizeLabel)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(garment.formattedPrice).font(.subheadline)
                    }
                }
            }

            Section("Livraison") {
                Label(order.deliveryMethod.label, systemImage: order.deliveryMethod.symbol)
                if order.deliveryMethod == .relayPoint && !order.relayPoint.isEmpty {
                    Text(order.relayPoint)
                }
                Text(order.shippingAddress.singleLine)
                    .foregroundStyle(.secondary)
            }

            Section("Paiement") {
                LabeledContent("Articles", value: Money.format(order.subtotalCents))
                LabeledContent("Livraison", value: Money.format(order.shippingCents))
                LabeledContent("Protection acheteur", value: Money.format(order.serviceFeeCents))
                LabeledContent("Total") {
                    Text(Money.format(order.totalCents)).font(.headline)
                }
                Text(order.paymentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(order.number)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: order.status)
    }

    private func timeline(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(OrderStatus.allCases, id: \.self) { status in
                let reached = order.status >= status
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(reached ? Theme.like : Color(.systemGray4))
                                .frame(width: 18, height: 18)
                            if reached {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                        if status != OrderStatus.allCases.last {
                            Rectangle()
                                .fill(order.status > status ? Theme.like : Color(.systemGray4))
                                .frame(width: 2, height: 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.label(for: order.deliveryMethod))
                            .font(.subheadline.weight(status == order.status ? .bold : .regular))
                            .foregroundStyle(reached ? Color.primary : Color.secondary)
                        if let date = order.date(of: status) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 6)
    }
}
