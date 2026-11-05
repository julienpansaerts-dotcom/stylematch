import SwiftUI

@main
struct StyleMatchApp: App {
    /// Supabase + Stripe si `AppConfig` est rempli, sinon mode démo.
    @State private var store: AppStore = {
        let backend = Backend.make()
        return AppStore(service: backend.service, auth: backend.auth)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.start() }
        }
    }
}
