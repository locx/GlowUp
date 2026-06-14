import XCTest
@testable import GlowKit

// Regression tests for the symlink-follow and version-suffix parsing fixes.
final class AdvancedScannerFixTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-advfix-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  func test_projectScannerDoesNotFollowSymlinks() throws {
    let fm = FileManager.default
    try fm.createDirectory(at: root.appending(path: "proj/node_modules"),
                           withIntermediateDirectories: true)
    // A symlink cycle back to the project root must not cause duplicates or escape.
    try fm.createSymbolicLink(at: root.appending(path: "proj/loop"),
                              withDestinationURL: root.appending(path: "proj"))
    let found = ProjectScanner.scan(roots: [root], artifacts: ["node_modules"])
    XCTAssertEqual(found.filter { $0.url.lastPathComponent == "node_modules" }.count, 1)
  }

  func test_duplicateExtensionHandlesPlatformSuffix() throws {
    let fm = FileManager.default
    let ext = root.appending(path: ".vscode/extensions")
    for name in ["ms.tool-1.0.0-darwin-arm64", "ms.tool-1.2.0-darwin-arm64"] {
      try fm.createDirectory(at: ext.appending(path: name), withIntermediateDirectories: true)
    }
    let found = DuplicateExtensionScanner.scan(home: root)
    // Same extension despite the platform suffix; only the older build is flagged.
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["ms.tool-1.0.0-darwin-arm64"])
  }

  func test_duplicateExtensionDoesNotFlagEqualVersions() throws {
    let fm = FileManager.default
    let ext = root.appending(path: ".vscode/extensions")
    // Two builds of the same version — neither should be flagged.
    for name in ["ms.tool-1.5.0-darwin-arm64", "ms.tool-1.5.0-darwin-x64"] {
      try fm.createDirectory(at: ext.appending(path: name), withIntermediateDirectories: true)
    }
    let found = DuplicateExtensionScanner.scan(home: root)
    XCTAssertTrue(found.isEmpty, "equal-version platform builds must not be flagged")
  }

  func test_duplicateExtensionFlagsOlderVersionWhenMixed() throws {
    let fm = FileManager.default
    let ext = root.appending(path: ".vscode/extensions")
    for name in ["ms.tool-1.0.0-darwin-arm64", "ms.tool-1.2.0-darwin-arm64"] {
      try fm.createDirectory(at: ext.appending(path: name), withIntermediateDirectories: true)
    }
    let found = DuplicateExtensionScanner.scan(home: root)
    // Only the strictly older version is flagged.
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["ms.tool-1.0.0-darwin-arm64"])
  }
}
