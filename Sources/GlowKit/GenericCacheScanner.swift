import Foundation

public enum GenericCacheScanner {
  // Subfolder names that are caches/logs by convention — the only things swept inside an app's data dir.
  private static let appSupportCacheNames = [
    "Cache", "Code Cache", "GPUCache", "GrShaderCache", "ShaderCache", "DawnCache",
    "Crashpad", "CachedData", "Cached Data", "CachedExtensionVSIXs", "logs", "Logs",
  ]

  public static func scan(home: URL) -> [Candidate] {
    var out = topLevelCaches(in: home.appending(path: "Library/Caches"), category: "appCaches")
    out += topLevelCaches(in: home.appending(path: "Library/Logs"), category: "systemLogs")
    out += appSupportCaches(home: home)
    out += containerCaches(home: home)
    return out.sortedByPath()
  }

  // Top-level entries under a throwaway root (Caches, Logs) — each a whole-dir candidate.
  private static func topLevelCaches(in root: URL, category: String) -> [Candidate] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
    ) else { return [] }

    var out: [Candidate] = []
    for url in entries {
      let name = url.lastPathComponent
      if name.hasPrefix(".") { continue }
      if let res = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
         res.isSymbolicLink == true { continue }
      // A whole opaque <bundle-id> dir is advanced-only; the name-declared subfolders stay safe.
      out.append(Candidate(
        ruleID: "\(category).\(name)", app: nil, category: category, risk: .rebuildable,
        why: "Files an app regenerates on demand.", url: url))
    }
    return out
  }

  // Sweep only cache-named subfolders inside each app — never the app dir or its data stores.
  private static func appSupportCaches(home: URL) -> [Candidate] {
    cacheSubfolders(under: home.appending(path: "Library/Application Support"),
                    relativeCachePaths: appSupportCacheNames)
  }

  // Sandboxed-app and group-container caches — only the Caches subfolder, never the data dir.
  private static func containerCaches(home: URL) -> [Candidate] {
    var out = cacheSubfolders(under: home.appending(path: "Library/Containers"),
                              relativeCachePaths: ["Data/Library/Caches"])
    out += cacheSubfolders(under: home.appending(path: "Library/Group Containers"),
                           relativeCachePaths: ["Library/Caches"])
    return out
  }

  // For each entry under `root`, emit any existing cache subfolder at `relativeCachePaths`.
  private static func cacheSubfolders(under root: URL, relativeCachePaths: [String]) -> [Candidate] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil, options: []
    ) else { return [] }

    var out: [Candidate] = []
    for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
      for rel in relativeCachePaths {
        let dir = entry.appending(path: rel)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
        out.append(Candidate(
          ruleID: "cache.\(entry.lastPathComponent).\(rel)", app: nil,
          category: "appCaches", risk: .safe,
          why: "Cached files an app regenerates on demand.", url: dir))
      }
    }
    return out
  }
}
