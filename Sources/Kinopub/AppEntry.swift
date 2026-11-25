import SwiftUI

@main
struct KinopubApp: App {
    @StateObject private var auth: AuthService
    @StateObject private var api: APIClient
    @StateObject private var player = PlayerCoordinator()

    init() {
        let auth = AuthService()
        _auth = StateObject(wrappedValue: auth)
        _api = StateObject(wrappedValue: APIClient(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .environmentObject(api)
            .environmentObject(player)
            .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
