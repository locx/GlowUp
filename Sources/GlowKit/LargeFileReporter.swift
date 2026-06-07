import Foundation

public enum LargeFileReporter {
  // Report-only: large files for the user to review; hidden files are never listed.
  public static func scan(dirs: [URL], minBytes: Int64) -> [Report] {
    let fm = FileManager.default
    var out: [Report] = []
    for dir in dirs {
      guard let entries = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
      for url in entries where !url.lastPathComponent.hasPrefix(".") {
        let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard v?.isRegularFile == true, let size = v?.fileSize, Int64(size) >= minBytes
        else { continue }
        out.append(Report(url: url, bytes: Int64(size)))
      }
    }
    return out.sorted { $0.bytes > $1.bytes }
  }
}
