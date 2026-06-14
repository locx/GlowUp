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
}
