import SwiftUI

@main
struct GhostBrowserApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(store)
        }
    }
}
