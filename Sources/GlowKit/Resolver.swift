import Foundation
import Darwin

public enum Resolver {
  // Expand a spec to existing, non-vetoed URLs under its base root.
  public static func resolve(_ spec: PathSpec, home: URL) -> [URL] {
    let segments = spec.glob.split(separator: "/").map(String.init)
    var frontier = [spec.base.url(home: home)]
    for seg in segments {
      if seg.contains("*") {
        frontier = frontier.flatMap { children($0, matching: seg) }
      } else {
        frontier = frontier.map { $0.appending(path: seg) }
      }
    }
    let fm = FileManager.default
    return frontier.filter { fm.fileExists(atPath: $0.path) }
                   .filter { !DenyList.vetoes($0, home: home) }
  }

  private static func children(_ dir: URL, matching pattern: String) -> [URL] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
    return names
      .filter { fnmatch(pattern, $0, 0) == 0 }
      .map { dir.appending(path: $0) }
  }
}
