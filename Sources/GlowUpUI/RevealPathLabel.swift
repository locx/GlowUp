import SwiftUI
import AppKit

// Reveals a file or folder in Finder. Centralized so every path the app shows is navigable
// the same way, and so an already-trashed item falls back to opening its parent instead of failing.
enum RevealInFinder {
  static func reveal(_ url: URL) {
    let parent = url.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: parent.path)
    } else {
      NSWorkspace.shared.open(parent)
    }
  }
}

// A path shown as a clickable label that reveals its target in Finder, with a hover affordance.
struct RevealPathLabel: View {
  let url: URL
  var font: Font = .caption
  var monospaced = false
  @State private var hovering = false

  var body: some View {
    Button { RevealInFinder.reveal(url) } label: {
      Text(url.path)
        .font(monospaced ? font.monospaced() : font)
        .foregroundStyle(hovering ? Color.brand : Color.textSecondary)
        .underline(hovering)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help("Reveal in Finder")
  }
}
