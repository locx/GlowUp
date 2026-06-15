import Foundation
import Darwin

public enum Resolver {
  // Expand a spec to existing, non-vetoed URLs under its base root.
  public static func resolve(_ spec: PathSpec, home: URL,
                             diagnostics: ScanDiagnostics? = nil) -> [URL] {
    let segments = spec.glob.split(separator: "/").map(String.init)
    // Re-checked here so the deny-list isn't the lone defense for specs built in code.
    guard !segments.contains("..") else { return [] }
    var frontier = [spec.base.url(home: home)]
    for seg in segments {
      if seg.contains("*") {
        frontier = frontier.flatMap { children($0, matching: seg, diagnostics: diagnostics) }
      } else {
        frontier = frontier.map { $0.appending(path: seg) }
      }
    }
    let fm = FileManager.default
    return frontier.filter { fm.fileExists(atPath: $0.path) }
                   .filter { !DenyList.vetoes($0, home: home) }
  }

  // Caps the wildcard fan-out so a pathological directory can't freeze the scan; a truncated
  // listing is incomplete, not unsafe — every survivor still faces the deny-list downstream.
  private static let maxChildren = 500

  private static func children(_ dir: URL, matching pattern: String,
                               diagnostics: ScanDiagnostics? = nil) -> [URL] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
      diagnostics?.recordFailure(dir)
      return []
    }
    let matches = names.filter { fnmatch(pattern, $0, 0) == 0 }
    if matches.count > maxChildren { diagnostics?.recordFailure(dir) }
    return matches.prefix(maxChildren).map { dir.appending(path: $0) }
  }
}
