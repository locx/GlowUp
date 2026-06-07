import XCTest
@testable import GlowKit

final class DuplicateExtensionScannerTests: XCTestCase {
  private var home: URL!
  private var ext: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-ext-\(UUID().uuidString)")
    ext = home.appending(path: ".vscode/extensions")
    for name in ["pub.tool-1.0.0", "pub.tool-1.2.0", "pub.tool-1.10.0",
                 "other.ext-2.0.0"] {
      try FileManager.default.createDirectory(
        at: ext.appending(path: name), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  func test_flagsOlderVersionsKeepingHighest() {
    let found = DuplicateExtensionScanner.scan(home: home)
    // 1.10.0 is highest; 1.0.0 and 1.2.0 flagged; the singleton other.ext kept.
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)),
                   ["pub.tool-1.0.0", "pub.tool-1.2.0"])
    XCTAssertEqual(found.first?.category, "duplicateExtensions")
  }
}
