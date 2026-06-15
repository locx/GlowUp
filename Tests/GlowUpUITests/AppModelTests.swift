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
    try Data(repeating: 0xCD, count: 4096).write(
      to: home.appending(path: "Library/Application Support/Code/WebStorage/blob"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
  }

  // Spies for the two non-reversible permanent ops. Fired flags let a test prove the default
  // (non-advanced) clean path never reaches the root rm / simctl operations.
  private final class SpyRoot: RootCommandRunner, @unchecked Sendable {
    var fired = false
    func runAsRoot(_ command: String) -> Bool { fired = true; return true }
  }
  private final class SpyShell: ShellRunner, @unchecked Sendable {
    var fired = false
    func run(_ launchPath: String, _ args: [String]) -> Bool { fired = true; return true }
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
                    storeURL: store,
                    rootRunner: rootSpy ?? AdminRunner(),
                    shellRunner: shellSpy ?? ProcessRunner())
  }

  // Must be set before model() — the initializer reads them, so a spy assigned later isn't injected.
  private var rootSpy: SpyRoot?
  private var shellSpy: SpyShell?

  func test_scanFindsCandidatesAndDefaultSelectsSafe() async throws {
    let m = try model()
    // Include all risks so both paths (safe + stateful) appear as candidates.
    await m.scan(includeRisks: Set(Risk.allCases))
    XCTAssertEqual(m.phase, .results)
    // Both paths resolve; only the safe one is selected by default.
    XCTAssertEqual(m.candidates.count, 2)
    XCTAssertEqual(m.selected.count, 1)
    XCTAssertGreaterThan(m.selectedBytes, 0)
  }

  func test_cleanTrashesSelectedRecordsBatchAndReportsFreed() async throws {
    let m = try model()
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
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
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    await m.cleanSelected()
    let result = await m.restoreLast()
    XCTAssertGreaterThan(result.restored, 0)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
  }

  func test_advancedScanIncludesProjectArtifacts() async throws {
    let fm = FileManager.default
    // Create a node_modules directory under a project root.
    let projects = home.appending(path: "projects")
    try fm.createDirectory(at: projects.appending(path: "app/node_modules"),
                           withIntermediateDirectories: true)
    try Data(repeating: 0xEF, count: 2048).write(
      to: projects.appending(path: "app/node_modules/pkg"))
    let catalogJSON = Data("""
    {
      "schemaVersion": 1,
      "rules": [],
      "projectRoots": ["~/projects"],
      "projectArtifacts": ["node_modules"]
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    let m = AppModel(catalog: cat, inventory: FakeInv(), home: home,
                     mover: BinMover(bin: bin), storeURL: store)

    // Advanced mode: node_modules must appear as a rebuildable candidate.
    m.advanced = true
    await m.scan(includeRisks: Risk.scanTiers(advanced: true))
    XCTAssertTrue(m.candidates.contains { $0.url.lastPathComponent == "node_modules" && $0.risk == .rebuildable },
                  "advanced scan should surface node_modules as rebuildable")

    // Non-advanced mode: node_modules must NOT appear.
    m.advanced = false
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    XCTAssertFalse(m.candidates.contains { $0.url.lastPathComponent == "node_modules" },
                   "basic scan must not include project artifacts")
  }

  // The menu-bar quick action must clean without replacing an open result set.
  func test_quickCleanLeavesReviewStateUntouched() async throws {
    let m = try model()
    await m.scan(includeRisks: Set(Risk.allCases))
    let candidatesBefore = m.candidates.map(\.id)

    let items = await m.quickScanSafe()
    XCTAssertFalse(items.isEmpty)
    await m.quickClean(items)

    XCTAssertEqual(m.phase, .results)
    XCTAssertEqual(m.candidates.map(\.id), candidatesBefore)
    XCTAssertGreaterThan(m.lastFreed, 0)
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)
  }

  // The quick-clean trash boundary must spare non-safe items even if handed in directly.
  func test_quickCleanNeverTrashesNonSafeItem() async throws {
    let m = try model()
    let safe = home.appending(path: "Library/Application Support/Code/CachedData")
    let stateful = home.appending(path: "Library/Application Support/Code/WebStorage")
    // Hand-built mixed input: bypasses the scan-time filter to exercise the boundary guard.
    await m.quickClean([(safe, 8192, .safe), (stateful, 4096, .stateful)])
    // Safe item trashed; stateful item spared and never recorded.
    XCTAssertFalse(FileManager.default.fileExists(atPath: safe.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: stateful.path))
    XCTAssertFalse(RestoreStore(storeURL: store).batches().contains { b in
      b.items.contains { $0.originalPath == stateful.path }
    }, "stateful item must never appear in a quick-clean batch")
  }

  func test_defaultCleanTrashesOnlySafe() async throws {
    let m = try model()
    // Include all risks so both safe and stateful candidates are present.
    await m.scan(includeRisks: Set(Risk.allCases))
    let safeCandidate = m.candidates.first { $0.risk == .safe }
    let statefulCandidate = m.candidates.first { $0.risk == .stateful }
    XCTAssertNotNil(safeCandidate)
    XCTAssertNotNil(statefulCandidate)
    // Default selection must contain only the safe candidate.
    XCTAssertEqual(m.selected, Set([safeCandidate!.id]))
    await m.cleanSelected()
    // Safe path trashed.
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
    // Stateful path remains on disk (was never selected).
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/WebStorage").path))
  }

  func test_cleanSelectedNeverTrashesStatefulEvenIfSelected() async throws {
    let m = try model()
    await m.scan(includeRisks: Set(Risk.allCases))
    let statefulCandidate = try XCTUnwrap(m.candidates.first { $0.risk == .stateful })
    // Force the stateful item into the selection; the tier filter must still spare it.
    m.selected = Set(m.candidates.map(\.id))
    await m.cleanSelected()
    // The stateful WebStorage path stays on disk despite being selected.
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/WebStorage").path))
    XCTAssertFalse(RestoreStore(storeURL: store).batches().contains { b in
      b.items.contains { $0.originalPath == statefulCandidate.url.path }
    }, "stateful candidate must never appear in a recorded cleanup batch")
  }

  func test_cleanSelectedInAdvancedSparesStatefulAndPrivacyButTrashesRebuildable() async throws {
    // Advanced mode widens cleanTiers to [.safe, .rebuildable]; stateful/privacy must still be spared
    // by the tier guard specifically (not merely excluded by basic mode's [.safe] filter).
    let fm = FileManager.default
    let appSupport = home.appending(path: "Library/Application Support/Code")
    for name in ["Build", "WebStorage", "Cookies"] {
      try fm.createDirectory(at: appSupport.appending(path: name), withIntermediateDirectories: true)
      try Data(repeating: 0xAB, count: 4096).write(to: appSupport.appending(path: "\(name)/blob"))
    }
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
          { "base": "appSupport", "glob": "Code/Build", "risk": "rebuildable" },
          { "base": "appSupport", "glob": "Code/WebStorage", "risk": "stateful" },
          { "base": "appSupport", "glob": "Code/Cookies", "risk": "privacy" }
        ]
      }],
      "projectRoots": [],
      "projectArtifacts": []
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    let m = AppModel(catalog: cat, inventory: FakeInv(), home: home,
                     mover: BinMover(bin: bin), storeURL: store)

    m.advanced = true
    await m.scan(includeRisks: Risk.scanTiers(advanced: true))
    let rebuildable = try XCTUnwrap(m.candidates.first { $0.risk == .rebuildable })
    let stateful = try XCTUnwrap(m.candidates.first { $0.risk == .stateful })
    let privacy = try XCTUnwrap(m.candidates.first { $0.risk == .privacy })

    // Force every candidate into the selection; the tier guard must still spare stateful + privacy.
    m.selected = Set(m.candidates.map(\.id))
    await m.cleanSelected()

    // Rebuildable IS trashed under Advanced.
    XCTAssertFalse(fm.fileExists(atPath: rebuildable.url.path),
                   "rebuildable candidate should be trashed in advanced mode")
    // Stateful and privacy remain on disk despite being selected.
    XCTAssertTrue(fm.fileExists(atPath: stateful.url.path),
                  "stateful candidate must never be trashed, even under Advanced")
    XCTAssertTrue(fm.fileExists(atPath: privacy.url.path),
                  "privacy candidate must never be trashed, even under Advanced")
    // Neither stateful nor privacy may appear in any recorded batch.
    let recorded = RestoreStore(storeURL: store).batches()
    XCTAssertTrue(recorded.contains { $0.items.contains { $0.originalPath == rebuildable.url.path } },
                  "rebuildable cleanup must be recorded")
    XCTAssertFalse(recorded.contains { b in
      b.items.contains { $0.originalPath == stateful.url.path || $0.originalPath == privacy.url.path }
    }, "stateful/privacy must never appear in a recorded cleanup batch")
  }

  func test_lastFreedCountsSamePathOnce() async throws {
    // Two rules that both resolve to the same URL — dedupe should keep one; freed == that size.
    let catalogJSON = Data("""
    {
      "schemaVersion": 1,
      "rules": [
        {
          "id": "rule1",
          "app": "VSCode",
          "appBundleID": "com.microsoft.VSCode",
          "requiresInstalled": true,
          "category": "appCaches",
          "risk": "safe",
          "why": "w",
          "paths": [{ "base": "appSupport", "glob": "Code/CachedData" }]
        },
        {
          "id": "rule2",
          "app": "VSCode2",
          "appBundleID": "com.microsoft.VSCode",
          "requiresInstalled": true,
          "category": "appCaches",
          "risk": "safe",
          "why": "w",
          "paths": [{ "base": "appSupport", "glob": "Code/CachedData" }]
        }
      ],
      "projectRoots": [],
      "projectArtifacts": []
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    let m = AppModel(catalog: cat, inventory: FakeInv(), home: home,
                     mover: BinMover(bin: bin), storeURL: store)
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    // Dedupe keeps exactly one candidate for the shared path.
    let matching = m.candidates.filter { $0.url.path.hasSuffix("CachedData") }
    XCTAssertEqual(matching.count, 1, "dedupe must keep a single candidate per path")
    // Select all and clean; freed must equal the single candidate's size (not doubled).
    m.selected = Set(m.candidates.map(\.id))
    await m.cleanSelected()
    let singleSize = m.sizes[matching[0].id] ?? 0
    XCTAssertEqual(m.lastFreed, singleSize, "lastFreed must not double-count deduplicated paths")
  }

  func test_restoreLastPublishesResult() async throws {
    let m = try model()
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    await m.cleanSelected()
    XCTAssertGreaterThan(m.lastFreed, 0)
    await m.restoreLast()
    // lastRestore must be published and show at least one restored item.
    XCTAssertNotNil(m.lastRestore)
    XCTAssertGreaterThan(m.lastRestore?.restored ?? 0, 0)
  }

  func test_historyAndRestoreByBatch() async throws {
    // Target the blob file (not a directory) so fileSizeKey returns real bytes.
    let catalogJSON = Data("""
    {
      "schemaVersion": 1,
      "rules": [{
        "id": "vscodeBlob",
        "app": "Visual Studio Code",
        "appBundleID": "com.microsoft.VSCode",
        "requiresInstalled": true,
        "category": "appCaches",
        "risk": "safe",
        "why": "w",
        "paths": [{ "base": "appSupport", "glob": "Code/CachedData/blob" }]
      }],
      "projectRoots": [],
      "projectArtifacts": []
    }
    """.utf8)
    let cat = try JSONDecoder().decode(Catalog.self, from: catalogJSON)
    let m = AppModel(catalog: cat, inventory: FakeInv(), home: home,
                     mover: BinMover(bin: bin), storeURL: store)
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    await m.cleanSelected()
    // The cached batches must contain the recorded batch.
    XCTAssertEqual(m.batches.count, 1)
    XCTAssertGreaterThan(m.totalReclaimedAllTime, 0)
    // restore(batch) must put items back and return > 0 restored.
    let result = await m.restore(m.batches[0])
    XCTAssertGreaterThan(result.restored, 0)
    // A fully-restored batch is dropped from history so it can't be re-restored or double-counted.
    XCTAssertTrue(m.batches.isEmpty)
    XCTAssertEqual(m.totalReclaimedAllTime, 0)
  }

  func test_cleanReportsTrashFailures() async throws {
    // Two safe caches: the mover throws on Cache2 and succeeds on CachedData — exercises failure recording
    // through the actually-cleanable path (the tier filter spares stateful items entirely).
    let fm = FileManager.default
    try fm.createDirectory(
      at: home.appending(path: "Library/Application Support/Code/Cache2"),
      withIntermediateDirectories: true)
    try Data(repeating: 0xEF, count: 4096).write(
      to: home.appending(path: "Library/Application Support/Code/Cache2/blob"))
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
          { "base": "appSupport", "glob": "Code/Cache2" }
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

    // Both safe caches are candidates.
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    XCTAssertEqual(m.candidates.count, 2)

    // Select all candidates so both are attempted.
    m.selected = Set(m.candidates.map(\.id))
    await m.cleanSelected()

    // Cache2 throws → at least one failure recorded.
    XCTAssertGreaterThanOrEqual(m.lastCleanFailures, 1)
    // CachedData succeeds → freed bytes > 0.
    XCTAssertGreaterThan(m.lastFreed, 0)
    // A batch containing the succeeded item was persisted.
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)
  }

  // The two non-reversible ops must be unreachable from the default clean path.
  func test_defaultCleanNeverFiresPermanentOps() async throws {
    let root = SpyRoot(); let shell = SpyShell()
    rootSpy = root; shellSpy = shell
    let m = try model()
    await m.scan(includeRisks: Risk.scanTiers(advanced: false))
    await m.cleanSelected()
    XCTAssertEqual(m.phase, .done)
    XCTAssertFalse(root.fired, "default cleanSelected must never invoke the root rm op")
    XCTAssertFalse(shell.fired, "default cleanSelected must never invoke simctl")
  }

  // The menu-bar quick action is also default-tier and must never reach the permanent ops.
  func test_quickCleanNeverFiresPermanentOps() async throws {
    let root = SpyRoot(); let shell = SpyShell()
    rootSpy = root; shellSpy = shell
    let m = try model()
    let items = await m.quickScanSafe()
    XCTAssertFalse(items.isEmpty)
    await m.quickClean(items)
    XCTAssertFalse(root.fired, "quickClean must never invoke the root rm op")
    XCTAssertFalse(shell.fired, "quickClean must never invoke simctl")
  }

  // Proves the injected seam is live: only the distinct Advanced-gated methods reach the runners.
  func test_permanentOpsRouteThroughInjectedRunners() async throws {
    let root = SpyRoot(); let shell = SpyShell()
    rootSpy = root; shellSpy = shell
    let m = try model()
    _ = await m.removeUnavailableSimulators()
    XCTAssertTrue(shell.fired, "removeUnavailableSimulators must use the injected shell runner")
    XCTAssertFalse(root.fired, "simulator removal must not touch the root runner")
  }
}

struct FakeInv: AppInventory {
  func isInstalled(bundleID: String) -> Bool { true }
  // Installed apps contribute name tokens, so their Library dirs aren't flagged as orphans.
  func knownSet() -> Set<String> { ["code"] }
}
struct BinMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
// Succeeds for all paths except those whose last component is "Cache2".
struct PartialMover: ItemMover {
  let bin: URL
  struct FakeError: Error {}
  func trash(_ url: URL) throws -> URL {
    if url.lastPathComponent == "Cache2" { throw FakeError() }
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}
