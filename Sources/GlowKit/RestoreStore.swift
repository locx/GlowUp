import Foundation

public struct RestoreStore {
  private let storeURL: URL

  public init(storeURL: URL) { self.storeURL = storeURL }

  // One canonical history location so the app and CLI always share restore state.
  public static var defaultStoreURL: URL {
    let support = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    return support.appending(path: "GlowUp/history.json")
  }

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

  // Drop a batch — a fully-restored cleanup is no longer in the Trash, so it must leave history.
  public func remove(_ id: String) {
    let remaining = load().filter { $0.id != id }
    guard let data = try? JSONEncoder().encode(remaining) else { return }
    try? data.write(to: storeURL, options: .atomic)
  }

  /// Moves a batch's items back and prunes the store to what is still in the Trash:
  /// the batch is removed on full success, or rewritten with only the failed items.
  public func restore(_ batch: CleanupBatch) -> (restored: Int, failed: [(TrashedItem, Error)]) {
    let fm = FileManager.default
    var restored = 0
    var failed: [(TrashedItem, Error)] = []
    // Restore ancestors before descendants so parent dirs exist before children move in.
    let ordered = batch.items.sorted { URL(fileURLWithPath: $0.originalPath).pathComponents.count < URL(fileURLWithPath: $1.originalPath).pathComponents.count }
    for item in ordered {
      let from = URL(fileURLWithPath: item.trashedPath)
      let to = URL(fileURLWithPath: item.originalPath)
      do {
        // Reuse guard for files only: a directory's mtime shifts when the OS touches its children
        // in the Trash, so the check would falsely reject valid folder restores.
        let isDir = (try? from.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDir, let recorded = item.modified,
           let current = try? from.resourceValues(forKeys: [.contentModificationDateKey])
                                  .contentModificationDate,
           abs(current.timeIntervalSince(recorded)) > 2 {
          throw CocoaError(.fileReadUnknown)
        }
        try fm.createDirectory(at: to.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.moveItem(at: from, to: to)
        restored += 1
      } catch {
        failed.append((item, error))
      }
    }
    // History must mirror the Trash, or a partial restore could be replayed against
    // files already put back and stay in the list forever.
    if failed.isEmpty {
      remove(batch.id)
    } else if restored > 0 {
      replaceItems(batch.id, with: failed.map(\.0))
    }
    return (restored, failed)
  }

  private func replaceItems(_ id: String, with items: [TrashedItem]) {
    var all = load()
    guard let i = all.firstIndex(where: { $0.id == id }) else { return }
    all[i] = CleanupBatch(id: all[i].id, date: all[i].date, items: items)
    guard let data = try? JSONEncoder().encode(all) else { return }
    try? data.write(to: storeURL, options: .atomic)
  }

  private func load() -> [CleanupBatch] {
    guard let data = try? Data(contentsOf: storeURL),
          let batches = try? JSONDecoder().decode([CleanupBatch].self, from: data)
    else { return [] }
    return batches
  }
}
