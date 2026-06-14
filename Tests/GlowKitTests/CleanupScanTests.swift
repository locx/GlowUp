import XCTest
@testable import GlowKit

// A vetted catalog rule must keep its category/tier across modes; the generic sweep may not
// relabel a Caches dir the catalog already names (the safe-vs-advanced consistency contract).
final class CleanupScanTests: XCTestCase {
  private struct StubInventory: AppInventory {
    func isInstalled(bundleID: String) -> Bool { false }
  }

  private var home: URL!
  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-pipe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: home.appending(path: "Library/Caches/Acme/Browser/Default/Cache"),
      withIntermediateDirectories: true)
    try Data(repeating: 7, count: 2048).write(
      to: home.appending(path: "Library/Caches/Acme/Browser/Default/Cache/blob"))
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  private func catalog() -> Catalog {
    let rule = Rule(
      id: "acme.netcache", app: "Acme", appBundleID: nil, requiresInstalled: nil,
      category: "browserData", risk: .safe, why: "w",
      paths: [PathSpec(base: .caches, glob: "Acme/Browser/*/Cache")])
    return Catalog(schemaVersion: 1, rules: [rule], projectRoots: [], projectArtifacts: [])
  }

  private func categories(advanced: Bool) -> Set<String> {
    let out = CleanupScan.candidates(
      home: home, catalog: catalog(), inventory: StubInventory(),
      includeRisks: Risk.scanTiers(advanced: advanced), advanced: advanced)
    return Set(out.map(\.category))
  }

  func test_catalogCategorySurvivesInBothModes() {
    XCTAssertTrue(categories(advanced: false).contains("browserData"))
    // The generic whole-dir sweep must not absorb the catalog dir and drop browserData.
    XCTAssertTrue(categories(advanced: true).contains("browserData"))
  }

  // Pins orphan sweeps to the rebuildable tier end-to-end: surfaced under advanced
  // tiers, absent from a safe-only scan.
  func test_orphanSweepsSurfaceOnlyWhenRebuildableRequested() throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: "Library/Application Support/OldLeftover"),
      withIntermediateDirectories: true)

    XCTAssertTrue(categories(advanced: true).contains("libraryOrphans"))
    XCTAssertFalse(categories(advanced: false).contains("libraryOrphans"))
  }
}
