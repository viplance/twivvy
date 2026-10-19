import SwiftUI

@main struct HamsterLabApp: App {
    @State private var game = GameModel()
    var body: some Scene {
        WindowGroup { ContentView(game: game).preferredColorScheme(.light) }
    }
}
