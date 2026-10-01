import SwiftUI

/// The app's scenes. The app target only holds the model and returns this.
public struct KingsideScene: Scene {
  let model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some Scene {
    #if os(macOS)
      mainWindow
        .defaultSize(
          width: model.catalog.interface.home.macWindowWidth,
          height: model.catalog.interface.home.macWindowHeight
        )
      Settings {
        NavigationStack { SettingsHome() }
          .frame(width: model.catalog.interface.settings.macWindowWidth)
          .environment(model)
          .environment(\.localization, model.localization)
      }
    #else
      mainWindow
    #endif
  }

  private var mainWindow: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .environment(\.localization, model.localization)
    }
    #if !os(tvOS)
      .commands { GameCommands(localization: model.localization) }
    #endif
  }
}
