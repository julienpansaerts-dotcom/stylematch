import SwiftUI

enum AppTab: Hashable {
    case discover, cart, shop, profile
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab: AppTab = .discover

    var body: some View {
        @Bindable var store = store

        TabView(selection: $selectedTab) {
            DiscoverView()
                .tabItem { Label("Découvrir", systemImage: "flame.fill") }
                .tag(AppTab.discover)

            CartView(onBrowse: { selectedTab = .discover })
                .tabItem { Label("Panier", systemImage: "bag.fill") }
                .badge(store.cart.count)
                .tag(AppTab.cart)

            if store.isAdmin {
                AdminView()
                    .tabItem { Label("Boutique", systemImage: "storefront.fill") }
                    .tag(AppTab.shop)
            }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            if let notice = store.notices.first {
                NoticeBanner(notice: notice) {
                    store.dismissNotice(notice.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(4))
                    store.dismissNotice(notice.id)
                }
            }
        }
        .animation(.spring(duration: 0.4), value: store.notices.first?.id)
        .sheet(item: $store.checkout, onDismiss: { store.checkoutDismissed() }) { request in
            CheckoutView(request: request)
        }
        .sheet(isPresented: $store.showSignIn) {
            SignInView()
        }
    }
}
