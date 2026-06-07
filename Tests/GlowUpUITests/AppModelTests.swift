import XCTest
import GlowKit
@testable import GlowUpUI

@MainActor
final class AppModelTests: XCTestCase {
  private var home: URL!
  private var store: URL!
  private var bin: URL!

  override func setUpWithError() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-app-\(UUID().uuidString)")
    home = root.appending(path: "home")
    store = root.appending(path: "history.json")
    bin = root.appending(path: "bin")
    let fm = FileManager.default
    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    // Materialize one safe cache (vscode) and one stateful path.
    try fm.createDirectory(
      at: home.appending(path: "Library/Application Support/Code/CachedData"),
      withIntermediateDirectories: true)
    try Data(repeating: 0xAB, count: 8192).write(
      to: home.appending(path: "Library/Application Support/Code/CachedData/blob"))
    try fm.createDirectory(
      at: home.appending(path: "Library/Application Support/Code/WebStorage"),
      withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
  }

  private func model() throws -> AppModel {
    // Catalog JSON: vscode rule with a safe CachedData path and a stateful WebStorage path.
    // Rule and Catalog are Codable-only (no memberwise init), so we construct via JSON.
    let catalogJSON = Data("""
    {
      "schemaVersion": 1,
      "rules": [{
        "id": "vscode",
        "app": "Visual Studio Code",
        "appBundleID": "com.microsoft.VSCode",
        "requiresInstalled": true,
        "category": "appCaches",
        "risk": "safe",
        "why": "w",
        "paths": [
          { "base": "appSupport", "glob": "Code/CachedData" },
          { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" }
        ]
      }],
      "projectRoots": [],
      "projectArtifacts": []
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    return AppModel(catalog: cat,
                    inventory: FakeInv(),
                    home: home,
                    mover: BinMover(bin: bin),
                    storeURL: store)
  }

  func test_scanFindsCandidatesAndDefaultSelectsSafe() async throws {
    let m = try model()
    await m.scan()
    XCTAssertEqual(m.phase, .results)
    // Both paths resolve; only the safe one is selected by default.
    XCTAssertEqual(m.candidates.count, 2)
    XCTAssertEqual(m.selected.count, 1)
    XCTAssertGreaterThan(m.selectedBytes, 0)
  }

  func test_cleanTrashesSelectedRecordsBatchAndReportsFreed() async throws {
    let m = try model()
    await m.scan()
    await m.cleanSelected()
    XCTAssertEqual(m.phase, .done)
    XCTAssertGreaterThan(m.lastFreed, 0)
    // The selected safe cache was moved out of home.
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
    // A batch was persisted.
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)
  }

  func test_restoreLastPutsItemsBack() async throws {
    let m = try model()
    await m.scan()
    await m.cleanSelected()
    let result = await m.restoreLast()
    XCTAssertGreaterThan(result.restored, 0)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
  }

  func test_cleanReportsTrashFailures() async throws {
    // Mover that throws for "WebStorage" but succeeds otherwise — exercises failure recording.
    let catalogJSON = Data("""
    {
      "schemaVersion": 1,
      "rules": [{
        "id": "vscode",
        "app": "Visual Studio Code",
        "appBundleID": "com.microsoft.VSCode",
        "requiresInstalled": true,
        "category": "appCaches",
        "risk": "safe",
        "why": "w",
        "paths": [
          { "base": "appSupport", "glob": "Code/CachedData" },
          { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" }
        ]
      }],
      "projectRoots": [],
      "projectArtifacts": []
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    let m = AppModel(catalog: cat,
                     inventory: FakeInv(),
                     home: home,
                     mover: PartialMover(bin: bin),
                     storeURL: store)

    // Scan with all risks so both CachedData (safe) and WebStorage (stateful) are candidates.
    await m.scan(includeRisks: Set(Risk.allCases))
    XCTAssertEqual(m.candidates.count, 2)

    // Select all candidates so both are attempted.
    m.selected = Set(m.candidates.map(\.id))
    await m.cleanSelected()

    // WebStorage throws → at least one failure recorded.
    XCTAssertGreaterThanOrEqual(m.lastCleanFailures, 1)
    // CachedData succeeds → freed bytes > 0.
    XCTAssertGreaterThan(m.lastFreed, 0)
    // A batch containing the succeeded item was persisted.
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)
  }
}

struct FakeInv: AppInventory { func isInstalled(bundleID: String) -> Bool { true } }
struct BinMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
// Succeeds for all paths except those whose last component is "WebStorage".
struct PartialMover: ItemMover {
  let bin: URL
  struct FakeError: Error {}
  func trash(_ url: URL) throws -> URL {
    if url.lastPathComponent == "WebStorage" { throw FakeError() }
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
