import XCTest
import GlowTestSupport
@testable import GlowKit

final class TrasherTests: XCTestCase {
  private var work: URL!
  private var bin: URL!     // stand-in trash directory

  override func setUpWithError() throws {
    work = TempDir.make("glow-trash")
    bin = try work.makeDir("_bin")
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
    let mover = BinMover(bin: bin)
    let result = Trasher(mover: mover).trash([(url: f, bytes: 42)])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertEqual(result.trashed[0].originalPath, f.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))      // moved out
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.trashed[0].trashedPath))
    // Caller-supplied byte count must be recorded as-is.
    XCTAssertEqual(result.trashed[0].bytes, 42)
    // Modification date must be captured from the trashed path.
    XCTAssertNotNil(result.trashed[0].modified)
  }

  func test_reportsFailureForMissingFileButKeepsGoing() throws {
    let good = try makeFile("good.txt")
    let missing = work.appending(path: "missing.txt")
    let result = Trasher(mover: BinMover(bin: bin)).trash([(url: missing, bytes: 0),
                                                            (url: good, bytes: 1)])

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

    let result = Trasher(mover: BinMover(bin: bin)).trash([(url: dir, bytes: 100)])

    XCTAssertEqual(result.trashed.count, 1)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))   // source gone
    let trashedDir = URL(fileURLWithPath: result.trashed[0].trashedPath)
    let trashedNested = trashedDir.appending(path: "sub/nested.txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: trashedNested.path))
    // Caller-supplied size must be recorded; modification date must be present.
    XCTAssertEqual(result.trashed[0].bytes, 100)
    XCTAssertNotNil(result.trashed[0].modified)
  }
}
