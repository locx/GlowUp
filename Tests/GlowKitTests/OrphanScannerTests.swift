import XCTest
@testable import GlowKit

final class OrphanScannerTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-orphan-\(UUID().uuidString)")
    for rel in ["Library/Application Support/KnownApp",
                "Library/Application Support/OldLeftover",
                "Library/Caches/com.known.app"] {
      try FileManager.default.createDirectory(
        at: home.appending(path: rel), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  func test_flagsUnknownEntriesOnly() {
    let found = OrphanScanner.scan(home: home, known: ["KnownApp", "com.known.app"])
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["OldLeftover"])
    XCTAssertEqual(found.first?.category, "libraryOrphans")
    XCTAssertNotEqual(found.first?.risk, .safe)        // never default-selected
  }

  func test_returnsEmptyWhenAllKnown() {
    let found = OrphanScanner.scan(home: home,
      known: ["KnownApp", "OldLeftover", "com.known.app"])
    XCTAssertTrue(found.isEmpty)
  }
}
