import BedtimeCore
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if let error = store.loadError {
                ContentUnavailableView(
                    "The week could not start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                switch store.screen {
                case .title:
                    TitleView()
                case .morning:
                    MorningView()
                case .event, .outcome:
                    PlayView()
                case .lifeline:
                    LifelineView()
                case .ending:
                    EndView()
                }
            }
        }
        .animation(.snappy, value: store.screen)
        .preferredColorScheme(store.engine?.state.phase == .night && store.screen != .ending ? .dark : nil)
    }
}
