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
    while let child = en.nextObject() as? URL {
      if Task.isCancelled { return total }
      total += allocated(child)
    }
    return total
  }

  // Measure many trees concurrently; one entry per input URL.
  public static func measure(_ urls: [URL]) async -> [URL: Int64] {
    let window = max(4, min(8, ProcessInfo.processInfo.activeProcessorCount))
    return await withTaskGroup(of: (URL, Int64).self) { group in
      var out = Dictionary<URL, Int64>(minimumCapacity: urls.count)
      var next = 0
      // Seed up to `window` tasks, then add one per completion to cap in-flight work.
      while next < urls.count && next < window {
        let url = urls[next]
        group.addTask { (url, await size(of: url)) }
        next += 1
      }
      for await (url, bytes) in group {
        // Stop seeding and drain on cancellation so the group tears down promptly.
        if Task.isCancelled { group.cancelAll(); break }
        out[url] = bytes
        if next < urls.count {
          let nextURL = urls[next]
          group.addTask { (nextURL, await size(of: nextURL)) }
          next += 1
        }
      }
      return out
    }
  }

  private static func allocated(_ url: URL) -> Int64 {
    let v = try? url.resourceValues(
      forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
    return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
  }
}
