import Foundation

// trashPathReused: the Trash path no longer holds the recorded item.
// historyUnreadable: the history file exists but won't decode, so appending would overwrite it.
public enum RestoreError: Error, Sendable { case trashPathReused, historyUnreadable }

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
  public func record(_ batch: CleanupBatch) throws {
    // Corrupt history throws .historyUnreadable; write failures rethrow — never a silent overwrite.
    try mutate { $0 + [batch] }
  }

  // The one mutation path: read-modify-write inside a single coordinated writing region so a
  // stale read can't drop a concurrent change. The transform returns nil to mean "no change, skip
  // the write". Throws .historyUnreadable on a present-but-corrupt file (never overwriting it) and
  // rethrows write failures.
  @discardableResult
  private func mutate(_ transform: ([CleanupBatch]) -> [CleanupBatch]?) throws -> Bool {
    try FileManager.default.createDirectory(
      at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var opError: Error?
    var wrote = false
    coordinator.coordinate(writingItemAt: storeURL, options: .forMerging,
                           error: &coordError) { url in
      do { wrote = try Self.applyTransform(transform, at: url) } catch { opError = error }
    }
    // Coordination unavailable: read-modify-write raw, but the corrupt-guard still applies.
    if coordError != nil { return try Self.applyTransform(transform, at: storeURL) }
    if let opError { throw opError }
    return wrote
  }

  // Decode current contents fresh, transform, then atomically rewrite. Returns whether a write
  // happened (false when the transform signals no change).
  private static func applyTransform(
    _ transform: ([CleanupBatch]) -> [CleanupBatch]?, at url: URL) throws -> Bool {
    // Absent file = first run; a present-but-undecodable file must abort, not be overwritten,
    // or the atomic rewrite below would permanently destroy prior restore history.
    var all: [CleanupBatch]
    if let data = try? Data(contentsOf: url) {
      guard let decoded = try? JSONDecoder().decode([CleanupBatch].self, from: data) else {
        throw RestoreError.historyUnreadable
      }
      all = decoded
    } else {
      all = []
    }
    guard let next = transform(all) else { return false }
    let data = try JSONEncoder().encode(next)
    try data.write(to: url, options: .atomic)
    return true
  }

  public func batches() -> [CleanupBatch] { load().reversed() }

  // Drop a batch — a fully-restored cleanup is no longer in the Trash, so it must leave history.
  // Returns whether the prune was persisted, so a swallowed write failure can't leave a stale batch.
  @discardableResult
  public func remove(_ id: String) -> Bool {
    // A corrupt or unwritable history must leave the batch in place rather than erase the file.
    do { try mutate { $0.filter { $0.id != id } }; return true }
    catch { return false }
  }

  /// Moves a batch's items back and prunes the store to what is still in the Trash:
  /// the batch is removed on full success, or rewritten with only the failed items.
  /// If every item fails, the batch is deliberately retained whole — those items are still
  /// in the Trash and remain restorable, so dropping it would lose recoverable history.
  public func restore(_ batch: CleanupBatch) -> (restored: Int, failed: [(TrashedItem, Error)], historyPruned: Bool) {
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
          throw RestoreError.trashPathReused
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
    // No prune is needed (all failed → batch retained) so that case is treated as pruned.
    var historyPruned = true
    if failed.isEmpty {
      historyPruned = remove(batch.id)
    } else if restored > 0 {
      historyPruned = replaceItems(batch.id, with: failed.map(\.0))
    }
    return (restored, failed, historyPruned)
  }

  // Returns whether the rewrite was persisted, so a swallowed failure can't leave stale items.
  @discardableResult
  private func replaceItems(_ id: String, with items: [TrashedItem]) -> Bool {
    // Returns nil (no write) when the id is absent, preserving the no-op-on-missing contract.
    do {
      return try mutate { all in
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        var next = all
        next[i] = CleanupBatch(id: next[i].id, date: next[i].date, items: items)
        return next
      }
    } catch { return false }
  }

  private func load() -> [CleanupBatch] {
    guard let data = readCoordinated(),
          let batches = try? JSONDecoder().decode([CleanupBatch].self, from: data)
    else { return [] }
    return batches
  }

  // Cross-process reads: coordinate so a concurrent writer can't hand us a torn file.
  private func readCoordinated() -> Data? {
    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var result: Data?
    coordinator.coordinate(readingItemAt: storeURL, options: .withoutChanges,
                           error: &coordError) { url in
      result = try? Data(contentsOf: url)
    }
    // Coordination unavailable must never be worse than the old raw read.
    if coordError != nil { return try? Data(contentsOf: storeURL) }
    return result
  }
}
