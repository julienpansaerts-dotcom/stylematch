import SwiftUI

/// Pile de cartes « à la Tinder » + barre d'actions.
///
/// ← gauche : passer · → droite : ajouter au panier · ↑ haut : acheter tout de suite
struct SwipeDeckView: View {
    @Environment(AppStore.self) private var store

    @State private var dragOffset: CGSize = .zero
    @State private var deckSize: CGSize = CGSize(width: 360, height: 560)
    @State private var isFlying = false
    @State private var detailGarment: Garment?

    private let horizontalThreshold: CGFloat = 110
    private let verticalThreshold: CGFloat = 130

    private struct DeckItem {
        let index: Int
        let garment: Garment
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack {
                    ForEach(visibleCards, id: \.garment.id) { item in
                        card(item)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { deckSize = geo.size }
                .onChange(of: geo.size) { _, newSize in deckSize = newSize }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            actionBar
        }
        .padding(.bottom, 10)
        .sheet(item: $detailGarment) { garment in
            GarmentDetailView(garment: garment) { direction in
                detailGarment = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    fly(direction)
                }
            }
        }
    }

    // MARK: - Cartes

    private var visibleCards: [DeckItem] {
        store.deck.prefix(3).enumerated()
            .map { DeckItem(index: $0.offset, garment: $0.element) }
            .reversed()
    }

    private var dragProgress: CGFloat {
        min(1, max(abs(dragOffset.width), abs(dragOffset.height)) / horizontalThreshold)
    }

    @ViewBuilder
    private func card(_ item: DeckItem) -> some View {
        let isTop = item.index == 0
        // Les cartes du dessous remontent pendant qu'on fait glisser celle du dessus.
        let depth = isTop ? 0 : CGFloat(item.index) - dragProgress

        GarmentCardView(
            garment: item.garment,
            dragOffset: isTop ? dragOffset : .zero,
            onOpenDetail: { detailGarment = item.garment }
        )
        .scaleEffect(1 - depth * 0.05)
        .offset(y: depth * 14)
        .offset(isTop ? dragOffset : .zero)
        .rotationEffect(.degrees(isTop ? Double(dragOffset.width / 18) : 0))
        .zIndex(Double(10 - item.index))
        .allowsHitTesting(isTop && !isFlying)
        .gesture(dragGesture)
    }

    // MARK: - Geste

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFlying else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isFlying else { return }
                if let direction = direction(for: value) {
                    fly(direction)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func direction(for value: DragGesture.Value) -> SwipeDirection? {
        let t = value.translation
        let predicted = value.predictedEndTranslation
        let verticalDominant = abs(t.height) > abs(t.width)

        if verticalDominant && -t.height > verticalThreshold { return .up }
        if t.width > horizontalThreshold || (predicted.width > horizontalThreshold * 2.5 && t.width > 40) { return .right }
        if t.width < -horizontalThreshold || (predicted.width < -horizontalThreshold * 2.5 && t.width < -40) { return .left }
        if verticalDominant && -predicted.height > verticalThreshold * 2.5 && -t.height > 50 { return .up }
        return nil
    }

    /// Fait partir la carte du dessus hors de l'écran puis applique l'action.
    private func fly(_ direction: SwipeDirection) {
        guard let top = store.deck.first, !isFlying else { return }
        isFlying = true

        let distanceX = max(deckSize.width, 300) * 1.6
        let distanceY = max(deckSize.height, 500) * 1.4
        let target: CGSize
        switch direction {
        case .left: target = CGSize(width: -distanceX, height: dragOffset.height + 60)
        case .right: target = CGSize(width: distanceX, height: dragOffset.height + 60)
        case .up: target = CGSize(width: dragOffset.width, height: -distanceY)
        }

        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset = target
        }

        Task {
            try? await Task.sleep(for: .milliseconds(280))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.swipe(top, direction)
                dragOffset = .zero
            }
            isFlying = false
        }
    }

    // MARK: - Barre d'actions

    private var actionBar: some View {
        HStack(alignment: .top, spacing: 18) {
            CircleActionButton(systemImage: "arrow.uturn.backward", color: Theme.undo, size: 46, label: "Retour") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    store.undoLastSwipe()
                }
            }
            .disabled(!store.canUndo || isFlying)

            CircleActionButton(systemImage: "xmark", color: Theme.pass, size: 64, label: "Passer") {
                fly(.left)
            }

            CircleActionButton(systemImage: "bolt.fill", color: Theme.buy, size: 52, label: "Acheter") {
                fly(.up)
            }

            CircleActionButton(systemImage: "bag.fill.badge.plus", color: Theme.like, size: 64, label: "Panier") {
                fly(.right)
            }
        }
        .disabled(store.deck.isEmpty)
    }
}
