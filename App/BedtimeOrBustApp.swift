import SwiftUI

// @MainActor: GameStore is main-actor isolated. iOS 18+ SDKs make App
// @MainActor already; the iOS 17 SDK (Xcode 15) does not.
@main
@MainActor
struct BedtimeOrBustApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
