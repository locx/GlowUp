import Foundation

// Subfolders that hold real app/user data, never pure cache. A dir containing any of these is
// left alone so a blunt sweep can't wipe WhatsApp/PWA state — shared by the cache and orphan scanners.
public enum DataStoreGuard {
  public static let names: Set<String> = [
    "Service Worker", "IndexedDB", "Local Storage", "Local Extension Settings",
    "Session Storage", "WebStorage", "databases", "Databases", "Cookies",
    "File System", "shared_proto_db", "blob_storage", "Sync Data", "WebsiteData",
  ]

  // Folded once so a store dir in nonstandard case (e.g. "indexeddb") still vetoes its parent.
  private static let lowerNames = Set(names.map { $0.lowercased() })

  // Depth-bounded: deeper costs a full walk for stores that effectively never nest that far.
  public static func holdsDataStore(_ dir: URL, depth: Int = 0) -> Bool {
    guard depth <= 3 else { return false }
    let fm = FileManager.default
    let kids: [String]
    do {
      kids = try fm.contentsOfDirectory(atPath: dir.path)
    } catch {
      return PathUtil.isPermissionDenied(error)
    }
    for k in kids {
      if lowerNames.contains(k.lowercased()) { return true }
      var isDir: ObjCBool = false
      let child = dir.appending(path: k)
      if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue,
         holdsDataStore(child, depth: depth + 1) { return true }
    }
    return false
  }
}
