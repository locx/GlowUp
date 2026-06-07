import Foundation

public enum SizeMeasurer {
  // Allocated bytes of a file or directory tree; returns early if cancelled.
  public static func size(of url: URL) async -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue { return allocated(url) }

    let keys: Set<URLResourceKey> = [.isRegularFileKey,
                                     .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
    var total: Int64 = 0
    for case let child as URL in en {
      if Task.isCancelled { return total }
      total += allocated(child)
    }
    return total
  }

  // Measure many trees concurrently; one entry per input URL.
  public static func measure(_ urls: [URL]) async -> [URL: Int64] {
    await withTaskGroup(of: (URL, Int64).self) { group in
      for url in urls { group.addTask { (url, await size(of: url)) } }
      var out: [URL: Int64] = [:]
      for await (url, bytes) in group { out[url] = bytes }
      return out
    }
  }

  private static func allocated(_ url: URL) -> Int64 {
    let v = try? url.resourceValues(
      forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
    return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
  }
}
