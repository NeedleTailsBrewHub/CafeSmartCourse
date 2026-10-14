import SwiftUI

struct ContentView: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(InventoryViewModel.self) var inventoryViewModel
    @Environment(MenuViewModel.self) var menuViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @State var didSignIn: Bool = false
    
    var body: some View {
        Group {
            if didSignIn {
#if os(macOS)
                MacHomeView()
#else
                HomeView()
#endif
            } else {
                Onboarding()
            }
        }
        .appAnimation(AppMotion.standard, value: didSignIn)
        .task {
            await authenticationViewModel.restoreSessionIfNeeded()
            didSignIn = authenticationViewModel.didSignIn
        }
        .onChange(of: authenticationViewModel.didSignIn) { _, newValue in
            withAnimation(AppMotion.standard) {
                self.didSignIn = newValue
            }
            if newValue {
                Task { @MainActor in
                    do {
                        try await inventoryViewModel.fetchInventory()
                        try await menuViewModel.fetchMenu()
                        try await orderViewModel.fetchOrders()
                    } catch {
                        logger.info("Bootstrap prefetch failed: \(error)")
                    }
                }
            }
        }
    }
}
