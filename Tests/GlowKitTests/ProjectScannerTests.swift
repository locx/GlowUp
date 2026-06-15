import XCTest
@testable import GlowKit

final class ProjectScannerTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-proj-\(UUID().uuidString)")
    for rel in ["app/node_modules/pkg", "app/src", "app/api/.venv/lib", "app/keep"] {
      try FileManager.default.createDirectory(
        at: root.appending(path: rel), withIntermediateDirectories: true)
    }
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  func test_findsArtifactDirsNotPlainDirs() {
    let found = ProjectScanner.scan(roots: [root],
      artifacts: ["node_modules", ".venv"])
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)), ["node_modules", ".venv"])
    XCTAssertEqual(found.first?.risk, .rebuildable)
    XCTAssertEqual(found.first?.category, "projectArtifacts")
  }

  func test_doesNotDescendIntoMatchedArtifact() {
    // 'pkg' lives inside node_modules and must not be reported separately.
    let found = ProjectScanner.scan(roots: [root], artifacts: ["node_modules"])
    XCTAssertFalse(found.contains { $0.url.lastPathComponent == "pkg" })
  }

  // A huge tree must not freeze the walk: the node cap stops it early and records the stop.
  func test_respectsNodeCapAndRecords() throws {
    for i in 0..<20 {
      try FileManager.default.createDirectory(
        at: root.appending(path: "deep/d\(i)/node_modules"), withIntermediateDirectories: true)
    }
    let diagnostics = ScanDiagnostics()
    let found = ProjectScanner.scan(roots: [root], artifacts: ["node_modules"],
                                    maxNodes: 3, diagnostics: diagnostics)
    XCTAssertLessThan(found.count, 20, "the cap must stop the walk before visiting every dir")
    XCTAssertFalse(diagnostics.failedDirectories.isEmpty, "hitting the cap must be recorded")
  }
}
