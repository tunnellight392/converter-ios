import SwiftUI

@main struct MyApp: App {
    /// Pinned categories and conversions, shared by the home and converter screens.
    @State private var favorites = Favorites()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(favorites)
        }
    }
}
