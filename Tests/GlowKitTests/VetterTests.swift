import XCTest
@testable import GlowKit

// The single safety gate. Swept (inferred) hits face the deny-list AND the data-store guard;
// catalog hits are pre-vetted and skip the data-store guard so they may name cache-in-store paths.
final class VetterTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-vet-\(UUID().uuidString)")
    try mkdir("Library/Caches/plain")
    try mkdir("Library/Caches/withstore/IndexedDB")
    try mkdir("Library/Caches/creds")
    try Data().write(to: home.appending(path: "Library/Caches/creds/secret.pem"))
    try mkdir("Documents/keep")
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  private func mkdir(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }
  private func cand(_ rel: String) -> Candidate {
    Candidate(ruleID: "t", app: nil, category: "appCaches", risk: .rebuildable,
              why: "x", url: home.appending(path: rel))
  }

  func test_sweptPlainCacheSurvives() {
    let out = Vetter.vet(catalog: [], swept: [cand("Library/Caches/plain")], home: home)
    XCTAssertEqual(out.count, 1)
  }

  func test_sweptDataStoreDirIsVetoed() {
    let out = Vetter.vet(catalog: [], swept: [cand("Library/Caches/withstore")], home: home)
    XCTAssertTrue(out.isEmpty, "a swept dir holding a data store must be dropped")
  }

  func test_sweptCredentialDirIsVetoed() {
    let out = Vetter.vet(catalog: [], swept: [cand("Library/Caches/creds")], home: home)
    XCTAssertTrue(out.isEmpty, "a swept dir holding a credential file must be dropped")
  }

  func test_protectedPathIsVetoedFromBothSides() {
    let c = cand("Documents/keep")
    XCTAssertTrue(Vetter.vet(catalog: [c], swept: [], home: home).isEmpty)
    XCTAssertTrue(Vetter.vet(catalog: [], swept: [c], home: home).isEmpty)
  }

  func test_catalogHitSkipsDataStoreGuard() {
    // Catalog deliberately names cache-in-store paths (e.g. a browser's Service Worker cache).
    let out = Vetter.vet(catalog: [cand("Library/Caches/withstore")], swept: [], home: home)
    XCTAssertEqual(out.count, 1, "catalog hits must not face the data-store guard")
  }

  func test_everyGuardedNameBlocksASweptCandidate() throws {
    // Each guarded name must drop a swept parent that contains it, or a rename/typo would
    // silently let live app state be swept.
    for name in DataStoreGuard.names {
      let parent = "Library/Caches/host-\(UUID().uuidString)"
      try mkdir("\(parent)/\(name)")
      let out = Vetter.vet(catalog: [], swept: [cand(parent)], home: home)
      XCTAssertTrue(out.isEmpty, "guarded name \(name) failed to drop its swept parent")
    }
  }

  func test_dataStoreGuardNameCountIsPinned() {
    // Pins the count so doc/code drift (a dropped or added name) fails CI.
    XCTAssertEqual(DataStoreGuard.names.count, 14)
  }

  func test_duplicateProtectedPathBothGetCachedVeto() {
    // Two candidates at the same protected path must both be vetoed; the per-scan memo must
    // not let a cached pass leak — neither survives.
    let a = cand("Documents/keep")
    let b = cand("Documents/keep")
    XCTAssertTrue(Vetter.vet(catalog: [a, b], swept: [], home: home).isEmpty)
  }

  func test_literalDotDotInputVetoedEvenAfterSiblingCached() {
    // A clean sibling caches first; a literal ".." input that lexically resolves to the same
    // protected dir must still be vetoed — the cache keys on the raw path, and DenyList's ".."
    // short-circuit fires before resolution, so the dirty input cannot borrow the clean verdict.
    let clean = cand("Library/Caches/plain")
    let traversal = Candidate(ruleID: "t", app: nil, category: "appCaches", risk: .rebuildable,
                              why: "x", url: home.appending(path: "Library/Caches/plain/../plain"))
    let out = Vetter.vet(catalog: [clean, traversal], swept: [], home: home)
    XCTAssertEqual(out.count, 1, "the clean path passes")
    XCTAssertFalse(out.contains { $0.url.path.contains("..") },
                   "the literal-.. input must be vetoed despite a cached clean sibling")
  }
}
