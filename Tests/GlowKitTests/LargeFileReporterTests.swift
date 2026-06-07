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
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  func test_reportsOnlyLargeNonHiddenFiles() {
    let reports = LargeFileReporter.scan(dirs: [dir], minBytes: 100_000)
    XCTAssertEqual(reports.map(\.url.lastPathComponent), ["big.bin"])
    XCTAssertGreaterThanOrEqual(reports.first?.bytes ?? 0, 100_000)
  }

  func test_emptyWhenNothingLarge() {
    XCTAssertTrue(LargeFileReporter.scan(dirs: [dir], minBytes: 10_000_000).isEmpty)
  }
}
