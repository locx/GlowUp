import XCTest
@testable import GlowKit

final class RestoreStoreTests: XCTestCase {
  private var dir: URL!
  private var store: URL!

  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-restore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    store = dir.appending(path: "history.json")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func batch(_ id: String, _ items: [TrashedItem]) -> CleanupBatch {
    CleanupBatch(id: id, date: Date(timeIntervalSince1970: 0), items: items)
  }

  func test_recordedBatchesPersistAndReloadNewestFirst() throws {
    let s1 = RestoreStore(storeURL: store)
    try s1.record(batch("one", []))
    try s1.record(batch("two", []))

    let s2 = RestoreStore(storeURL: store)     // fresh instance = reload from disk
    XCTAssertEqual(s2.batches().map(\.id), ["two", "one"])
  }

  func test_restoreMovesItemsBackAndCountsSuccesses() throws {
    // Simulate trashed state: original gone, trashed copy present.
    let original = dir.appending(path: "doc.txt")
    let trashed = dir.appending(path: "_bin/doc.txt")
    try FileManager.default.createDirectory(
      at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: trashed)

    let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path)
    let s = RestoreStore(storeURL: store)
    let result = s.restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 1)
    XCTAssertTrue(result.failed.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path))
  }

  func test_restoreReportsFailureWhenOriginalPathOccupied() throws {
    // Pins that restore never clobbers a file that reoccupied the original path.
    let original = dir.appending(path: "occupied.txt")
    let trashed = dir.appending(path: "_bin/occupied.txt")
    try FileManager.default.createDirectory(
      at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("trashed-content".utf8).write(to: trashed)
    try Data("occupier-content".utf8).write(to: original)  // path already taken

    let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path)
    let result = RestoreStore(storeURL: store).restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 0)
    XCTAssertEqual(result.failed.count, 1)
    // Original occupier must be untouched.
    XCTAssertEqual(try String(contentsOf: original), "occupier-content")
    // Trashed copy must still exist (not consumed by a failed move).
    XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
  }

  func test_restoreReportsPartialFailureWhenTrashEmptied() throws {
    let gonePath = dir.appending(path: "_bin/gone.txt").path   // never created
    let item = TrashedItem(originalPath: dir.appending(path: "gone.txt").path,
                           trashedPath: gonePath)
    let result = RestoreStore(storeURL: store).restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 0)
    XCTAssertEqual(result.failed.count, 1)
    XCTAssertEqual(result.failed[0].0, item)
  }

  // History must track the Trash: a partial restore keeps only the failed items.
  func test_partialRestorePrunesRestoredItemsFromStore() throws {
    let okOriginal = dir.appending(path: "ok.txt")
    let okTrashed = dir.appending(path: "_bin/ok.txt")
    try FileManager.default.createDirectory(
      at: okTrashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("ok".utf8).write(to: okTrashed)
    let ok = TrashedItem(originalPath: okOriginal.path, trashedPath: okTrashed.path)
    let gone = TrashedItem(originalPath: dir.appending(path: "gone.txt").path,
                           trashedPath: dir.appending(path: "_bin/gone.txt").path)

    let s = RestoreStore(storeURL: store)
    try s.record(batch("b", [ok, gone]))
    let result = s.restore(batch("b", [ok, gone]))

    XCTAssertEqual(result.restored, 1)
    XCTAssertEqual(result.failed.count, 1)
    XCTAssertEqual(s.batches().map(\.id), ["b"])
    XCTAssertEqual(s.batches().first?.items, [gone])
  }

  // A fully restored batch must leave history without the caller having to remove it.
  func test_fullRestoreRemovesBatchFromStore() throws {
    let original = dir.appending(path: "full.txt")
    let trashed = dir.appending(path: "_bin/full.txt")
    try FileManager.default.createDirectory(
      at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: trashed)
    let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path)

    let s = RestoreStore(storeURL: store)
    try s.record(batch("b", [item]))
    let result = s.restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 1)
    XCTAssertTrue(result.historyPruned)
    XCTAssertTrue(s.batches().isEmpty)
  }

  // A present-but-corrupt history file must abort record(), never be overwritten.
  func test_recordRefusesToOverwriteUndecodableHistory() throws {
    try Data("{ not json".utf8).write(to: store)
    let s = RestoreStore(storeURL: store)
    XCTAssertThrowsError(try s.record(batch("b", []))) { error in
      XCTAssertEqual(error as? RestoreError, .historyUnreadable)
    }
    // The corrupt bytes must survive untouched so a recovery tool can still read them.
    XCTAssertEqual(try String(contentsOf: store), "{ not json")
  }

  // The prune path must honor the same corrupt-history guard as record(): a remove() against an
  // undecodable file must refuse to write, so still-restorable history is never erased to [].
  func test_removeRefusesToClobberUndecodableHistory() throws {
    let s = RestoreStore(storeURL: store)
    try s.record(batch("one", []))
    try s.record(batch("two", []))
    // Corrupt the file after it held two valid batches.
    try Data("{ not json".utf8).write(to: store)

    XCTAssertFalse(s.remove("one"))
    // The corrupt bytes must survive untouched, not be overwritten with an empty/pruned history.
    XCTAssertEqual(try String(contentsOf: store), "{ not json")
  }

  func test_restoreFailsWhenTrashedFileMtimeDiffersFromRecorded() throws {
    // A different file placed at the reused Trash path must not be moved.
    let original = dir.appending(path: "orig.txt")
    let trashed  = dir.appending(path: "_bin/orig.txt")
    try FileManager.default.createDirectory(
      at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("content".utf8).write(to: trashed)

    // Record a stale modification date that will not match the on-disk mtime.
    let staleDate = Date(timeIntervalSince1970: 0)
    let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path,
                           bytes: 7, modified: staleDate)
    let result = RestoreStore(storeURL: store).restore(batch("b", [item]))

    XCTAssertEqual(result.restored, 0)
    XCTAssertEqual(result.failed.count, 1)
    XCTAssertEqual(result.failed[0].1 as? RestoreError, .trashPathReused)
    // Trashed file must still be present — the failed guard must not consume it.
    XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
  }
}
