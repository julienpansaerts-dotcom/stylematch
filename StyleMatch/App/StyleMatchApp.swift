import SwiftUI

@main
struct StyleMatchApp: App {
    /// Pour brancher le vrai backend, remplace `MockMarketplaceService()`
    /// par ton implémentation de `MarketplaceService` (ex. Supabase).
    @State private var store = AppStore(service: MockMarketplaceService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.start() }
        }
    }
}
