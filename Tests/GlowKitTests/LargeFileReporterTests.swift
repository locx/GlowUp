import XCTest
@testable import GlowKit

final class LargeFileReporterTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-large-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 200_000).write(to: dir.appending(path: "big.bin"))
    try Data(repeating: 0, count: 10).write(to: dir.appending(path: "small.bin"))
    try Data(repeating: 0, count: 200_000).write(to: dir.appending(path: ".secret"))
    // Nested large file: must be discovered by the recursive walk.
    let sub = dir.appending(path: "sub/deeper")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 300_000).write(to: sub.appending(path: "nested.bin"))
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  func test_reportsLargeNonHiddenFilesIncludingNested() {
    let reports = LargeFileReporter.scan(dirs: [dir], minBytes: 100_000)
    XCTAssertEqual(Set(reports.map(\.url.lastPathComponent)), ["big.bin", "nested.bin"])
    // Largest first, and the deep file was reached.
    XCTAssertEqual(reports.first?.url.lastPathComponent, "nested.bin")
  }

  func test_emptyWhenNothingLarge() {
    XCTAssertTrue(LargeFileReporter.scan(dirs: [dir], minBytes: 10_000_000).isEmpty)
  }

  func test_doesNotFollowSymlinkedSubdirectories() throws {
    let fm = FileManager.default
    let outside = dir.deletingLastPathComponent().appending(path: "glow-outside-\(UUID().uuidString)")
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: outside) }
    try Data(repeating: 0, count: 150_000).write(to: outside.appending(path: "outside-big.bin"))
    try fm.createSymbolicLink(at: dir.appending(path: "link"), withDestinationURL: outside)

    let names = Set(LargeFileReporter.scan(dirs: [dir], minBytes: 100_000).map(\.url.lastPathComponent))
    XCTAssertFalse(names.contains("outside-big.bin"), "a symlinked dir must not let the walk escape the tree")
  }
}
