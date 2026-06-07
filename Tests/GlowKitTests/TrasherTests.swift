import XCTest
@testable import GlowKit

final class TrasherTests: XCTestCase {
  private var work: URL!
  private var bin: URL!     // stand-in trash directory

  override func setUpWithError() throws {
    work = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-trash-\(UUID().uuidString)")
    bin = work.appending(path: "_bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: work)
  }
  private func makeFile(_ name: String) throws -> URL {
    let u = work.appending(path: name)
    try Data("x".utf8).write(to: u)
    return u
  }

  func test_trashesFilesAndReportsTrashedItems() throws {
    let f = try makeFile("a.txt")
    let mover = FakeMover(bin: bin)
    let result = Trasher(mover: mover).trash([f])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertEqual(result.trashed[0].originalPath, f.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))      // moved out
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.trashed[0].trashedPath))
  }

  func test_reportsFailureForMissingFileButKeepsGoing() throws {
    let good = try makeFile("good.txt")
    let missing = work.appending(path: "missing.txt")
    let result = Trasher(mover: FakeMover(bin: bin)).trash([missing, good])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertEqual(result.trashed[0].originalPath, good.path)
    XCTAssertEqual(result.failures.count, 1)
    XCTAssertEqual(result.failures[0].0.path, missing.path)
  }

  func test_trashesDirectoryTree() throws {
    // Verify that a directory and its nested contents are moved as a unit.
    let dir = work.appending(path: "mydir")
    let nested = dir.appending(path: "sub/nested.txt")
    try FileManager.default.createDirectory(
      at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("y".utf8).write(to: nested)

    let result = Trasher(mover: FakeMover(bin: bin)).trash([dir])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))   // source gone
    let trashedDir = URL(fileURLWithPath: result.trashed[0].trashedPath)
    let trashedNested = trashedDir.appending(path: "sub/nested.txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: trashedNested.path))
  }
}

// Moves into a temp directory instead of the real Trash.
struct FakeMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let dest = bin.appending(path: url.lastPathComponent)
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
