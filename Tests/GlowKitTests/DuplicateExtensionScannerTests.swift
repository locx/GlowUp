import XCTest
import GlowTestSupport
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

  func test_flagsOlderVersionsKeepingTheActiveOne() throws {
    try home.writeVSCodeRegistry(["pub.tool": "pub.tool-1.10.0", "other.ext": "other.ext-2.0.0"])
    let found = DuplicateExtensionScanner.scan(home: home)
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)),
                   ["pub.tool-1.0.0", "pub.tool-1.2.0"])
    XCTAssertEqual(found.first?.category, "duplicateExtensions")
  }

  // The live install is not the highest-numbered copy on disk: a newer copy must never be trashed.
  func test_neverTrashesActiveCopyWhenNewerExistsOnDisk() throws {
    try home.writeVSCodeRegistry(["pub.tool": "pub.tool-1.2.0"])
    let flagged = Set(DuplicateExtensionScanner.scan(home: home).map(\.url.lastPathComponent))
    XCTAssertFalse(flagged.contains("pub.tool-1.2.0"))   // active, kept
    XCTAssertFalse(flagged.contains("pub.tool-1.10.0"))  // newer than active, kept
    XCTAssertEqual(flagged, ["pub.tool-1.0.0"])          // only the strictly-older copy
  }

  // No authoritative registry → flag nothing rather than guess which copy is live.
  func test_flagsNothingWithoutRegistry() {
    XCTAssertTrue(DuplicateExtensionScanner.scan(home: home).isEmpty)
  }
}
