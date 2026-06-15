import Foundation

public enum ProjectScanner {
  // Artifact dirs under project roots; does not recurse into a matched artifact.
  public static func scan(roots: [URL], artifacts: Set<String>,
                          maxDepth: Int = 6, maxNodes: Int = 10_000,
                          diagnostics: ScanDiagnostics? = nil) -> [Candidate] {
    let fm = FileManager.default
    var out: [Candidate] = []
    var visited = 0
    for root in roots { walk(root, depth: 0, fm: fm, artifacts: artifacts, maxDepth: maxDepth,
                             maxNodes: maxNodes, visited: &visited, diagnostics: diagnostics, out: &out) }
    return out.sortedByPath()
  }

  private static func walk(_ dir: URL, depth: Int, fm: FileManager,
                           artifacts: Set<String>, maxDepth: Int, maxNodes: Int,
                           visited: inout Int, diagnostics: ScanDiagnostics? = nil,
                           out: inout [Candidate]) {
    guard depth <= maxDepth else { return }
    // Bound total directory visits so a giant tree can't freeze the scan; a capped walk is
    // incomplete, not unsafe — matched artifacts still pass the gate downstream.
    guard visited < maxNodes else { diagnostics?.recordFailure(dir); return }
    visited += 1
    guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
      diagnostics?.recordFailure(dir)
      return
    }
    for entry in entries {
      let vals = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      // Skip symlinks so the walk can't escape the root or loop.
      guard vals?.isDirectory == true, vals?.isSymbolicLink != true else { continue }
      if artifacts.contains(entry.lastPathComponent) {
        out.append(Candidate(ruleID: "project.\(entry.lastPathComponent)", app: nil,
                             category: "projectArtifacts", risk: .rebuildable,
                             why: "Rebuilt from source on demand.", url: entry))
      } else {
        walk(entry, depth: depth + 1, fm: fm, artifacts: artifacts, maxDepth: maxDepth,
             maxNodes: maxNodes, visited: &visited, diagnostics: diagnostics, out: &out)
      }
    }
  }
}
