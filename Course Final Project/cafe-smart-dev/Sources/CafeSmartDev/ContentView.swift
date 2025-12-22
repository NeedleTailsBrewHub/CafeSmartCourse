import SwiftUI

struct ContentView: View {
    
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
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
        .onChange(of: authenticationViewModel.didSignIn) { _, newValue in
            self.didSignIn = newValue
        }
    }
}
