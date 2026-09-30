import ChessUI
import SwiftUI

/// The app is a shell: `ChessUI` builds the model and every screen.
@main
struct KingsideApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        KingsideScene(model: model)
    }
}
