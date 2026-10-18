import SwiftUI

@main struct TwivvyApp: App {
    @State private var game = GameModel()
    var body: some Scene {
        WindowGroup { ContentView(game:game).preferredColorScheme(.dark) }
    }
}
