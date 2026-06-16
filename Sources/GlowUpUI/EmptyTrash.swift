import Foundation

// Wraps the user-initiated "Empty Trash" action via Finder AppleScript.
// Invoked only when the user explicitly taps the Empty Trash button — never automatically.
public enum EmptyTrash {
  // Reports the real outcome so a denied or failed Finder empty isn't shown to the user as success.
  @discardableResult
  public static func empty() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "tell application \"Finder\" to empty trash"]
    do { try p.run(); p.waitUntilExit() } catch { return false }
    return p.terminationStatus == 0
  }
}
