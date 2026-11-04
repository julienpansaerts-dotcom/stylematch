import SwiftUI

/// Onglet principal : la pile de vêtements à swiper.
struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.deck.isEmpty {
                if store.isLoadingDeck {
                    Spacer()
                    ProgressView("Chargement des pièces…")
                    Spacer()
                } else {
                    emptyState
                }
            } else {
                SwipeDeckView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showFilters) {
            FiltersView()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack {
            Button {
                Task { await store.reviewPassed() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) { CountBadge(count: store.passedCount) }
            }
            .disabled(store.passedCount == 0)
            .accessibilityLabel("Revoir les vêtements passés")

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Theme.brandGradient)
                Text("StyleMatch")
                    .font(.title2.weight(.heavy))
            }

            Spacer()

            Button {
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) { CountBadge(count: store.filters.activeCount) }
            }
            .accessibilityLabel("Filtres")
        }
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Pile vide

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Plus rien à swiper", systemImage: "hanger")
        } description: {
            Text("Tu as vu toutes les pièces qui correspondent à tes filtres. De nouvelles pièces uniques arrivent chaque jour !")
        } actions: {
            if store.passedCount > 0 {
                Button {
                    Task { await store.reviewPassed() }
                } label: {
                    Label("Revoir les vêtements passés (\(store.passedCount))", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            Button("Modifier les filtres") { showFilters = true }
                .buttonStyle(.bordered)
        }
    }
}
