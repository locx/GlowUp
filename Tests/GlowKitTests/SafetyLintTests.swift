import XCTest
@testable import GlowKit

// Proves no shipped rule can resolve onto protected data, and that the
// deny-list actually fires against planted bait.
final class SafetyLintTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glowlint-\(UUID().uuidString)")
    for bait in ["Documents/keep.txt", "Desktop/keep", ".ssh/id_rsa"] {
      let u = home.appending(path: bait)
      try FileManager.default.createDirectory(
        at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: u)
    }
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  func test_noShippedRuleResolvesOntoProtectedData() throws {
    let cat = try CatalogLoader.loadBundled()
    for rule in cat.rules {
      for spec in rule.paths {
        for url in Resolver.resolve(spec, home: home) {
          XCTAssertFalse(DenyList.vetoes(url, home: home),
                         "rule \(rule.id) resolved a vetoed path: \(url.path)")
        }
      }
    }
  }

  func test_baitFilesAreVetoed() {
    for bait in ["Documents/keep.txt", "Desktop/keep", ".ssh/id_rsa"] {
      XCTAssertTrue(DenyList.vetoes(home.appending(path: bait), home: home))
    }
  }

  // The sweepers infer candidates by shape, so the gate — not each scanner — must reject
  // credential dirs, live data stores, and symlinks planted inside the sweep roots.
  func test_sweepersNeverSurviveTheGateOntoDangerousData() throws {
    let fm = FileManager.default
    func mk(_ rel: String) throws {
      try fm.createDirectory(at: home.appending(path: rel), withIntermediateDirectories: true)
    }
    try mk("Library/Caches/plaincache")
    try mk("Library/Caches/hascreds")
    try Data().write(to: home.appending(path: "Library/Caches/hascreds/key.pem"))
    try mk("Library/Caches/hasstore/IndexedDB")
    try mk("Library/Application Support/Leftover/Local Storage")

    var swept = GenericCacheScanner.scan(home: home)
    swept += OrphanScanner.scan(home: home, known: [])
    swept += WorkspaceStorageScanner.scan(home: home)
    swept += DuplicateExtensionScanner.scan(home: home)

    let vetted = Vetter.vet(catalog: [], swept: swept, home: home)
    for c in vetted {
      XCTAssertFalse(DenyList.vetoes(c.url, home: home), "gate let a vetoed path through: \(c.url.path)")
      XCTAssertFalse(DataStoreGuard.holdsDataStore(c.url), "gate let a data store through: \(c.url.path)")
    }
    let survivingNames = Set(vetted.map(\.url.lastPathComponent))
    XCTAssertFalse(survivingNames.contains("hascreds"))
    XCTAssertFalse(survivingNames.contains("hasstore"))
    XCTAssertFalse(survivingNames.contains("Leftover"))
  }

  // Ensures shipped rules resolve actual paths when materialized, and that
  // none of those paths land on deny-listed locations.
  func test_shippedRulesResolveCleanlyWhenMaterialized() throws {
    let cat = try CatalogLoader.loadBundled()
    let fm = FileManager.default
    var resolvedCount = 0
    for rule in cat.rules {
      for spec in rule.paths {
        // Expand '*' segments to a concrete name so the path actually exists.
        let concrete = spec.glob.split(separator: "/")
          .map { $0.contains("*") ? "Default" : String($0) }.joined(separator: "/")
        let dir = spec.base.url(home: home).appending(path: concrete)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in Resolver.resolve(spec, home: home) {
          resolvedCount += 1
          XCTAssertFalse(DenyList.vetoes(url, home: home),
                         "rule \(rule.id) resolved a vetoed path: \(url.path)")
        }
      }
    }
    XCTAssertGreaterThan(resolvedCount, 15,
                         "safety-lint resolved too few paths to be meaningful")
  }
}
