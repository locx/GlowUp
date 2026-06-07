import Foundation

public struct RestoreStore {
  private let storeURL: URL

  public init(storeURL: URL) { self.storeURL = storeURL }

  // Append a batch; newest entries are returned first by `batches()`.
  // Single-writer: assumes the app serializes record/restore; concurrent records would lose-update the history.
  public func record(_ batch: CleanupBatch) throws {
    var all = load()
    all.append(batch)
    let data = try JSONEncoder().encode(all)
    try FileManager.default.createDirectory(
      at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: storeURL, options: .atomic)
  }

  public func batches() -> [CleanupBatch] { load().reversed() }

  public func restore(_ batch: CleanupBatch) -> (restored: Int, failed: [(TrashedItem, Error)]) {
    let fm = FileManager.default
    var restored = 0
    var failed: [(TrashedItem, Error)] = []
    for item in batch.items {
      let from = URL(fileURLWithPath: item.trashedPath)
      let to = URL(fileURLWithPath: item.originalPath)
      do {
        try fm.createDirectory(at: to.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.moveItem(at: from, to: to)
        restored += 1
      } catch {
        failed.append((item, error))
      }
    }
    return (restored, failed)
  }

  private func load() -> [CleanupBatch] {
    guard let data = try? Data(contentsOf: storeURL),
          let batches = try? JSONDecoder().decode([CleanupBatch].self, from: data)
    else { return [] }
    return batches
  }
}
