import Foundation
import GlowKit

// Unique temp directory per call so parallel tests never share state; created eagerly.
public enum TempDir {
  @discardableResult
  public static func make(_ prefix: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "\(prefix)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

public extension URL {
  // Create a subdirectory at a relative path under this URL (returns the new dir).
  @discardableResult
  func makeDir(_ rel: String) throws -> URL {
    let dir = appending(path: rel)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // Write a VSCode extensions.json under this URL mapping extension id -> active directory name.
  @discardableResult
  func writeVSCodeRegistry(_ active: [String: String]) throws -> URL {
    let ext = try makeDir(".vscode/extensions")
    let entries = active.map { id, rel in ["identifier": ["id": id], "relativeLocation": rel] }
    try JSONSerialization.data(withJSONObject: entries)
      .write(to: ext.appending(path: "extensions.json"))
    return ext
  }

  // Create intermediate dirs then write `bytes` at a relative path (returns the file URL).
  @discardableResult
  func writeFile(_ rel: String, bytes: Data) throws -> URL {
    let file = appending(path: rel)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: file)
    return file
  }
}

public extension Catalog {
  // Build a catalog from a JSON literal via the public loader, so fixtures need no @testable access.
  static func decode(_ json: String) throws -> Catalog {
    try CatalogLoader.load(data: Data(json.utf8))
  }
}
