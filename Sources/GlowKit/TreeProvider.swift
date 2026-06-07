import Foundation

public struct TreeNode: Sendable, Identifiable, Equatable {
  public let url: URL
  public let name: String
  public let isDirectory: Bool

  public var id: String { url.path }

  public init(url: URL, name: String, isDirectory: Bool) {
    self.url = url; self.name = name; self.isDirectory = isDirectory
  }
}

public enum TreeProvider {
  // Immediate, non-vetoed children of a directory (one level; lazy by design).
  public static func children(of url: URL, home: URL) -> [TreeNode] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey]
    guard let entries = try? fm.contentsOfDirectory(
      at: url, includingPropertiesForKeys: keys) else { return [] }
    return entries
      .filter { !DenyList.vetoes($0, home: home) }
      .map { child in
        let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return TreeNode(url: child, name: child.lastPathComponent, isDirectory: isDir)
      }
      .sorted { $0.name < $1.name }
  }
}
