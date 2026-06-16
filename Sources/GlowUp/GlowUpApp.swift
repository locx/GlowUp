import SwiftUI
import GlowUpUI

@main
struct GlowUpApp: App {
  @StateObject private var model = AppModel.live()

  var body: some Scene {
    WindowGroup(id: "main") {
      ContentView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 960, height: 640)
    .windowResizability(.contentMinSize)

    // Menu-bar extra: reclaimable at a glance plus a safe-only quick clean.
    MenuBarExtra("GlowUp", systemImage: "sparkles") {
      MenuBarContent(model: model)
    }
  }
}

// A real View so @Environment(\.openWindow) is injected — it is never populated on the App struct.
private struct MenuBarContent: View {
  @ObservedObject var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    // Reclaimable at a glance.
    if model.selectedBytes > 0 {
      Text("\(ReclaimLabel.format(model.selectedBytes)) reclaimable safely")
        .foregroundStyle(.secondary)
    } else {
      Text("Nothing to clean right now").foregroundStyle(.secondary)
    }
    Divider()
    Button("Clean Safe Items Now") {
      Task {
        // Separate safe-only pipeline: an Advanced result set open in the main window survives.
        let items = await model.quickScanSafe()
        let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
        guard bytes > 0, confirmQuickClean(bytes: bytes) else { return }
        await model.quickClean(items)
      }
    }
    .disabled(model.isBusy)
    Button("Open GlowUp…") {
      // Recreate the window if it was closed; activation alone can't bring back a closed WindowGroup.
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Divider()
    Button("Quit") { NSApp.terminate(nil) }
  }

  // Trashing always sits behind an explicit confirm, even from the menu bar.
  private func confirmQuickClean(bytes: Int64) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Move \(ReclaimLabel.format(bytes)) of safe items to the Trash?"
    alert.informativeText = "Caches and logs only. You can put everything back from History."
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
  }
}
