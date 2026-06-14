import Foundation

// Runs a shell command as root via one macOS admin prompt.
public protocol RootCommandRunner: Sendable {
  func runAsRoot(_ command: String) -> Bool
}

public struct AdminRunner: RootCommandRunner {
  public init() {}
  public func runAsRoot(_ command: String) -> Bool {
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
  }
}

// System-cache cleanup: deletes /Library/Caches contents as root. NOT recoverable — there is no
// Trash for root deletions; the scope guard below is the only safety, so it is deliberately strict.
public enum SystemCacheCleaner {
  static let root = "/Library/Caches"

  public static func totalBytes() async -> Int64 {
    let urls = topLevelEntries()
    let sizes = await SizeMeasurer.measure(urls)
    return urls.reduce(0) { $0 + (sizes[$1] ?? 0) }
  }

  @discardableResult
  public static func cleanAll(runner: RootCommandRunner = AdminRunner()) -> Bool {
    clean(topLevelEntries(), runner: runner)
  }

  // `root` is injectable only so tests can exercise the runner seam against a temp dir; production
  // call sites default to /Library/Caches, leaving real behavior unchanged.
  private static func topLevelEntries(root: String = root) -> [URL] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
    return names.filter { !$0.hasPrefix(".") }
      .map { URL(fileURLWithPath: root).appending(path: $0) }
  }

  @discardableResult
  static func clean(_ urls: [URL], runner: RootCommandRunner, root: String = root) -> Bool {
    guard let cmd = removalCommand(urls, root: root) else { return false }
    return runner.runAsRoot(cmd)
  }

  // Refuse unless EVERY path is a direct child of `root` — bounds a root rm to that dir.
  static func removalCommand(_ urls: [URL], root: String = root) -> String? {
    guard !urls.isEmpty else { return nil }
    var args: [String] = []
    for u in urls {
      // Resolve symlinks before the scope check so a link whose target leaves the root can't pass.
      let p = PathUtil.canonicalPath(u)
      guard p.hasPrefix(root + "/"),
            URL(fileURLWithPath: p).deletingLastPathComponent().path == root,
            !p.contains("/..") else { return nil }
      args.append("'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'")
    }
    return "/bin/rm -rf " + args.joined(separator: " ")
  }
}
