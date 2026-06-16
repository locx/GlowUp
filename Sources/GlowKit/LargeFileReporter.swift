import Foundation

public enum LargeFileReporter {
  // Report-only: large files for the user to review; hidden files and package internals are skipped.
  // Recurses into subfolders so a big file nested deep is still surfaced; the node cap bounds a
  // pathological tree — a truncated listing is incomplete, not unsafe (nothing here is ever cleaned).
  public static func scan(dirs: [URL], minBytes: Int64, maxNodes: Int = 50_000) -> [Report] {
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
    var out: [Report] = []
    for dir in dirs {
      guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys),
                                   options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { continue }
      var visited = 0
      for case let url as URL in en {
        visited += 1
        if visited > maxNodes { break }
        let v = try? url.resourceValues(forKeys: keys)
        // Don't descend or report symlinks, so the walk can't escape the chosen folder.
        if v?.isSymbolicLink == true { en.skipDescendants(); continue }
        guard v?.isRegularFile == true, let size = v?.fileSize, Int64(size) >= minBytes else { continue }
        out.append(Report(url: url, bytes: Int64(size)))
      }
    }
    return out.sorted { $0.bytes > $1.bytes }
  }
}
