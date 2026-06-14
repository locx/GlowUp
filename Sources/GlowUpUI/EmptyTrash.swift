import Foundation

// Wraps the user-initiated "Empty Trash" action via Finder AppleScript.
// Invoked only when the user explicitly taps the Empty Trash button — never automatically.
public enum EmptyTrash {
  public static func empty() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "tell application \"Finder\" to empty trash"]
    // Wait so callers can re-stat the real outcome instead of assuming success.
    do { try p.run(); p.waitUntilExit() } catch {}
  }

  // Item count in the user's Trash, so the Empty Trash button can disable when there's nothing to empty.
  public static func itemCount() -> Int {
    let fm = FileManager.default
    guard let url = try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: false),
          let items = try? fm.contentsOfDirectory(atPath: url.path)
    else { return 0 }
    return items.filter { $0 != ".DS_Store" }.count
  }
}
