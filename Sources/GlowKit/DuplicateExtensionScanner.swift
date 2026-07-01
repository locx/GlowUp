import Foundation

public enum DuplicateExtensionScanner {
  // Trusts VSCode's own extensions.json for which copy is live, so cleanup can never trash the
  // build VSCode is actually using — version numbers alone can disagree with what's activated.
  public static func scan(home: URL, diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let fm = FileManager.default
    let dir = home.appending(path: ".vscode/extensions")
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
      diagnostics?.recordFailure(dir)
      return []
    }
    // Absent registry isn't a read failure (no extensions, or non-VSCode home), so stay quiet.
    guard let active = activeLocations(dir: dir) else { return [] }

    var out: [Candidate] = []
    for name in names where !name.hasPrefix(".") {
      guard let dash = versionDash(name) else { continue }
      let ext = String(name[..<dash])
      guard let liveName = active[ext], liveName != name,
            let liveDash = versionDash(liveName) else { continue }
      let version = parseVersion(name[name.index(after: dash)...])
      let liveVersion = parseVersion(liveName[liveName.index(after: liveDash)...])
      // Keep anything at or above the live version (e.g. a staged update not yet activated).
      guard lexLess(version, liveVersion) else { continue }
      let url = dir.appending(path: name)
      out.append(Candidate(ruleID: "dupext.\(ext)", app: "Visual Studio Code",
                           category: "duplicateExtensions", risk: .safe,
                           why: "Superseded by the active installed version.", url: url))
    }
    return out.sortedByPath()
  }

  // Maps extension id -> the directory name VSCode records as installed, from extensions.json.
  // Returns nil when the file is absent or unparseable, so the caller can stay conservative.
  private static func activeLocations(dir: URL) -> [String: String]? {
    let url = dir.appending(path: "extensions.json")
    guard let data = try? Data(contentsOf: url),
          let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }
    var map: [String: String] = [:]
    for e in entries {
      guard let id = (e["identifier"] as? [String: Any])?["id"] as? String else { continue }
      if let rel = e["relativeLocation"] as? String {
        map[id] = rel
      } else if let loc = e["location"] as? [String: Any], let path = loc["fsPath"] as? String {
        map[id] = (path as NSString).lastPathComponent
      }
    }
    return map.isEmpty ? nil : map
  }

  private static func parseVersion<S: StringProtocol>(_ s: S) -> [Int] {
    // Leading digits per segment, so suffixes like -darwin-arm64 don't poison the compare.
    s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
  }

  // Version begins at the first '-' immediately followed by a digit.
  private static func versionDash(_ name: String) -> String.Index? {
    var i = name.startIndex
    while let dash = name[i...].firstIndex(of: "-") {
      let after = name.index(after: dash)
      if after < name.endIndex, name[after].isNumber { return dash }
      i = after
    }
    return nil
  }

  // Component-wise numeric version compare (1.10.0 > 1.2.0).
  private static func lexLess(_ a: [Int], _ b: [Int]) -> Bool {
    for i in 0..<max(a.count, b.count) {
      let l = i < a.count ? a[i] : 0, r = i < b.count ? b[i] : 0
      if l != r { return l < r }
    }
    return false
  }
}
