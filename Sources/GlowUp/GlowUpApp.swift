import SwiftUI
import GlowUpUI

@main
struct GlowUpApp: App {
  @StateObject private var model = AppModel.live()

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 960, height: 640)

    MenuBarExtra("GlowUp", systemImage: "sparkles") {
      Button("Open GlowUp…") { NSApp.activate(ignoringOtherApps: true) }
      Divider()
      Button("Quit") { NSApp.terminate(nil) }
    }
  }
}
