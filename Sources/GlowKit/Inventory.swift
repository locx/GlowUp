import AppKit

public protocol AppInventory: Sendable {
  func isInstalled(bundleID: String) -> Bool
  /// Token set used by OrphanScanner to recognise app-owned Library entries.
  func knownSet() -> Set<String>
}

public extension AppInventory {
  func knownSet() -> Set<String> { [] }
}

public final class SystemInventory: AppInventory, @unchecked Sendable {
  // Caches the /Applications walk so a second scan in the same session doesn't redo it; the lock
  // guards the cache because knownSet() is read from the scan's background task.
  private let lock = NSLock()
  private var cachedKnownSet: Set<String>?
  // Injectable so a test can count how often the expensive walk runs; nil means scan the real apps.
  private let knownSetProducer: (@Sendable () -> Set<String>)?

  public init() { knownSetProducer = nil }
  init(knownSetProducer: @escaping @Sendable () -> Set<String>) { self.knownSetProducer = knownSetProducer }

  public func isInstalled(bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }

  public func knownSet() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    if let cached = cachedKnownSet { return cached }
    let set = knownSetProducer?() ?? installedKnownSet()
    cachedKnownSet = set
    return set
  }

  /// Token set broad enough to attribute Library entries to their owning app
  /// without requiring exact bundle-ID matches.
  public func installedKnownSet() -> Set<String> {
    let fm = FileManager.default
    let appDirs = [
      URL(fileURLWithPath: "/Applications"),
      FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
      URL(fileURLWithPath: "/System/Applications"),
    ]
    var tokens = Set<String>()

    func addString(_ s: String) {
      let lc = s.lowercased()
      tokens.insert(lc)
      // Tokens shorter than 3 chars substring-match too broadly to be safe.
      for part in lc.components(separatedBy: CharacterSet(charactersIn: " ."))
        where part.count >= 3 {
        tokens.insert(part)
      }
    }

    for appDir in appDirs {
      guard let enumerator = fm.enumerator(
        at: appDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else { continue }

      for case let url as URL in enumerator {
        // Cap traversal at depth 3 relative to the app directory root.
        if enumerator.level > 3 { enumerator.skipDescendants(); continue }

        guard url.pathExtension == "app",
              let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              vals.isDirectory == true else { continue }

        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary else {
          enumerator.skipDescendants()
          continue
        }
        if let bid = info["CFBundleIdentifier"] as? String { addString(bid) }
        let name = (info["CFBundleName"] as? String)
          ?? url.deletingPathExtension().lastPathComponent
        addString(name)
        enumerator.skipDescendants()
      }
    }
    return tokens
  }
}
