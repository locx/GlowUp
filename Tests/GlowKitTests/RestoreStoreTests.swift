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
}
