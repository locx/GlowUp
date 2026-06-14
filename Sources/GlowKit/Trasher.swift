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

  // Moves each item to the Trash, recording the caller-supplied byte count and the
  // destination's modification date (one stat) for later Trash-path-reuse detection.
  public func trash(_ items: [(url: URL, bytes: Int64)]) -> (trashed: [TrashedItem], failures: [(URL, Error)]) {
    var trashed: [TrashedItem] = []
    var failures: [(URL, Error)] = []
    for item in items {
      do {
        let dest = try mover.trash(item.url)
        let modified = try? dest.resourceValues(forKeys: [.contentModificationDateKey])
                                .contentModificationDate
        trashed.append(TrashedItem(originalPath: item.url.path, trashedPath: dest.path,
                                   bytes: item.bytes, modified: modified))
      } catch {
        failures.append((item.url, error))
      }
    }
    return (trashed, failures)
  }
}
