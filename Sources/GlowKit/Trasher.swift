import Foundation

public protocol ItemMover: Sendable {
  // Move to the Trash, returning the resulting trashed location.
  func trash(_ url: URL) throws -> URL
}

public struct SystemMover: ItemMover {
  public init() {}

  public func trash(_ url: URL) throws -> URL {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    // trashItem may report success without a URL; treat as failure, never crash.
    guard let resulting else { throw CocoaError(.fileWriteUnknown) }
    return resulting as URL
  }
}

public struct Trasher {
  private let mover: ItemMover

  public init(mover: ItemMover = SystemMover()) { self.mover = mover }

  public func trash(_ urls: [URL]) -> (trashed: [TrashedItem], failures: [(URL, Error)]) {
    var trashed: [TrashedItem] = []
    var failures: [(URL, Error)] = []
    for url in urls {
      do {
        let dest = try mover.trash(url)
        trashed.append(TrashedItem(originalPath: url.path, trashedPath: dest.path))
      } catch {
        failures.append((url, error))
      }
    }
    return (trashed, failures)
  }
}
