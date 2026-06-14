import Foundation

public enum ProjectScanner {
  // Artifact dirs under project roots; does not recurse into a matched artifact.
  public static func scan(roots: [URL], artifacts: Set<String>,
                          maxDepth: Int = 6) -> [Candidate] {
    let fm = FileManager.default
    var out: [Candidate] = []
    for root in roots { walk(root, depth: 0, fm: fm, artifacts: artifacts,
                              maxDepth: maxDepth, out: &out) }
    return out.sortedByPath()
  }

  private static func walk(_ dir: URL, depth: Int, fm: FileManager,
                           artifacts: Set<String>, maxDepth: Int,
                           out: inout [Candidate]) {
    guard depth <= maxDepth,
          let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
    for entry in entries {
      let vals = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      // Skip symlinks so the walk can't escape the root or loop.
      guard vals?.isDirectory == true, vals?.isSymbolicLink != true else { continue }
      if artifacts.contains(entry.lastPathComponent) {
        out.append(Candidate(ruleID: "project.\(entry.lastPathComponent)", app: nil,
                             category: "projectArtifacts", risk: .rebuildable,
                             why: "Rebuilt from source on demand.", url: entry))
      } else {
        walk(entry, depth: depth + 1, fm: fm, artifacts: artifacts,
             maxDepth: maxDepth, out: &out)
      }
    }
  }
}
