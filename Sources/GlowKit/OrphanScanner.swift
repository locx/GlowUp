import Foundation

public enum OrphanScanner {
  // Possible leftovers: appSupport/caches children not in the known-owned set.
  public static func scan(home: URL, known: Set<String>) -> [Candidate] {
    let fm = FileManager.default
    var out: [Candidate] = []
    for base in [BaseRoot.appSupport, .caches] {
      let root = base.url(home: home)
      guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
      for name in names where !known.contains(name) && !name.hasPrefix(".") {
        let url = root.appending(path: name)
        guard !DenyList.vetoes(url, home: home) else { continue }
        out.append(Candidate(ruleID: "orphan.\(name)", app: name,
                             category: "libraryOrphans", risk: .rebuildable,
                             why: "Possible leftover — owning app not found.", url: url))
      }
    }
    return out.sorted { $0.url.path < $1.url.path }
  }
}
