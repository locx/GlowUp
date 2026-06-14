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

  // The overlap filter is bidirectional: a swept hit nested UNDER a catalog path and a swept hit
  // that is an ANCESTOR of a catalog path must both be dropped in favour of the catalog rule.
  func test_overlapFilterDropsBothNestingDirections() throws {
    let fm = FileManager.default
    // Swept-under-catalog: catalog names appSupport/BigApp (whole dir); the generic sweep emits
    // BigApp/Cache beneath it.
    try fm.createDirectory(
      at: home.appending(path: "Library/Application Support/BigApp/Cache"),
      withIntermediateDirectories: true)
    // Catalog-under-swept: the generic sweep emits the top-level Caches/Vendor dir; catalog names
    // Caches/Vendor/Inner beneath it.
    try fm.createDirectory(
      at: home.appending(path: "Library/Caches/Vendor/Inner"),
      withIntermediateDirectories: true)

    let rules = [
      Rule(id: "acme.netcache", app: "Acme", appBundleID: nil, requiresInstalled: nil,
           category: "browserData", risk: .safe, why: "w",
           paths: [PathSpec(base: .caches, glob: "Acme/Browser/*/Cache")]),
      Rule(id: "bigapp", app: "BigApp", appBundleID: nil, requiresInstalled: nil,
           category: "appData", risk: .safe, why: "w",
           paths: [PathSpec(base: .appSupport, glob: "BigApp")]),
      Rule(id: "vendor", app: "Vendor", appBundleID: nil, requiresInstalled: nil,
           category: "appCaches", risk: .safe, why: "w",
           paths: [PathSpec(base: .caches, glob: "Vendor/Inner")]),
    ]
    let cat = Catalog(schemaVersion: 1, rules: rules, projectRoots: [], projectArtifacts: [])
    let out = CleanupScan.candidates(
      home: home, catalog: cat, inventory: StubInventory(),
      includeRisks: Risk.scanTiers(advanced: true), advanced: true)
    let paths = Set(out.map { $0.url.resolvingSymlinksInPath().path })
    let asup = home.appending(path: "Library/Application Support").resolvingSymlinksInPath().path
    let caches = home.appending(path: "Library/Caches").resolvingSymlinksInPath().path

    XCTAssertTrue(paths.contains("\(asup)/BigApp"), "catalog BigApp survives")
    XCTAssertFalse(paths.contains("\(asup)/BigApp/Cache"),
                   "swept descendant of a catalog path must be dropped")
    XCTAssertTrue(paths.contains("\(caches)/Vendor/Inner"), "catalog Vendor/Inner survives")
    XCTAssertFalse(paths.contains("\(caches)/Vendor"),
                   "swept ancestor of a catalog path must be dropped")
  }
}
