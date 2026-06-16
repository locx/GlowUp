import XCTest
import GlowTestSupport
@testable import GlowKit

final class ScannerTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = TempDir.make("glow-scan")
    try home.makeDir("Library/Caches/Code/CachedData")
    try home.makeDir("Library/Application Support/Code/WebStorage")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func catalog(requiresInstalled: Bool) -> Catalog {
    let rule = Rule(
      id: "vscode.caches", app: "Visual Studio Code",
      appBundleID: "com.microsoft.VSCode",
      requiresInstalled: requiresInstalled, category: "appCaches",
      risk: .safe, why: "Regenerated on next launch.",
      paths: [
        PathSpec(base: .caches, glob: "Code/CachedData"),
        PathSpec(base: .appSupport, glob: "Code/WebStorage", risk: .stateful),
      ])
    return Catalog(schemaVersion: 1, rules: [rule],
                   projectRoots: [], projectArtifacts: [])
  }

  func test_defaultScanReturnsOnlySafeTierPaths() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: false),
                          inventory: FakeInventory(installed: []))
    let found = scanner.scan(home: home)               // default: [.safe]
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["CachedData"])
    XCTAssertEqual(found.first?.risk, .safe)
    XCTAssertEqual(found.first?.app, "Visual Studio Code")
  }

  func test_includingStatefulReturnsBothPaths() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: false),
                          inventory: FakeInventory(installed: []))
    let found = scanner.scan(home: home, includeRisks: [.safe, .stateful])
    XCTAssertEqual(Set(found.map(\.url.lastPathComponent)),
                   ["CachedData", "WebStorage"])
  }

  func test_requiresInstalledSkipsRuleWhenAppAbsent() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: true),
                          inventory: FakeInventory(installed: []))
    XCTAssertTrue(scanner.scan(home: home, includeRisks: Set(Risk.allCases)).isEmpty)
  }

  func test_requiresInstalledKeepsRuleWhenAppPresent() {
    let scanner = Scanner(catalog: catalog(requiresInstalled: true),
                          inventory: FakeInventory(installed: ["com.microsoft.VSCode"]))
    XCTAssertFalse(scanner.scan(home: home).isEmpty)
  }
}
