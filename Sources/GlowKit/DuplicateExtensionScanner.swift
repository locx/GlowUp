import Foundation

public enum DuplicateExtensionScanner {
  // Older versions of the same VSCode extension under ~/.vscode/extensions.
  public static func scan(home: URL, diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let fm = FileManager.default
    let dir = home.appending(path: ".vscode/extensions")
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
      diagnostics?.recordFailure(dir)
      return []
    }

    // Group dir names by extension id (publisher.name), keeping each version.
    var groups: [String: [(version: [Int], name: String)]] = [:]
    for name in names where !name.hasPrefix(".") {
      guard let dash = versionDash(name) else { continue }
      let ext = String(name[..<dash])
      // Leading digits per segment, so suffixes like -darwin-arm64 don't poison the compare.
      let version = name[name.index(after: dash)...]
        .split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
      groups[ext, default: []].append((version, name))
    }

    var out: [Candidate] = []
    for (ext, versions) in groups where versions.count > 1 {
      guard let maxVersion = versions.map(\.version).max(by: lexLess) else { continue }
      // Only flag entries whose version is strictly less than the max; equal versions
      // (e.g. same release with different platform suffixes) are kept.
      for v in versions where lexLess(v.version, maxVersion) {
        let url = dir.appending(path: v.name)
        out.append(Candidate(ruleID: "dupext.\(ext)", app: "Visual Studio Code",
                             category: "duplicateExtensions", risk: .safe,
                             why: "Superseded by a newer installed version.", url: url))
      }
    }
    return out.sortedByPath()
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
