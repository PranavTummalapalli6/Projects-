import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        NavigationStack {
            SplashScreenView()
                .environmentObject(authViewModel)
        }
    }
}
