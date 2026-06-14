import XCTest
import GlowKit
@testable import GlowUpCLI

final class CLIRunTests: XCTestCase {
  private var home: URL!
  private var store: URL!
  private var bin: URL!

  // Paths created in setUp for testing multiple scenarios.
  private var safeCacheURL: URL!
  private var privacyURL: URL!
  private var nodeModulesURL: URL!

  override func setUpWithError() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-cli-\(UUID().uuidString)")
    home = root.appending(path: "home")
    store = root.appending(path: "history.json")
    bin = root.appending(path: "bin")
    let fm = FileManager.default
    try fm.createDirectory(at: bin, withIntermediateDirectories: true)

    // Safe-tier: VSCode CachedData
    safeCacheURL = home.appending(path: "Library/Application Support/Code/CachedData")
    try fm.createDirectory(at: safeCacheURL, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(to: safeCacheURL.appending(path: "x"))

    // Privacy-tier: a catalog rule marked privacy (never trashed by CLI)
    privacyURL = home.appending(path: "Library/Safari/Fakedata")
    try fm.createDirectory(at: privacyURL, withIntermediateDirectories: true)
    try Data(repeating: 2, count: 1024).write(to: privacyURL.appending(path: "y"))

    // Rebuildable project artifact: node_modules under a project root
    let projectRoot = home.appending(path: "projects/myapp")
    nodeModulesURL = projectRoot.appending(path: "node_modules")
    try fm.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 512).write(to: nodeModulesURL.appending(path: "z"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
  }

  // Catalog that covers both a safe-tier path AND a privacy-tier path, plus project roots.
  private func catalogJSON() -> Catalog {
    let projectsPath = home.appending(path: "projects").path
    let s = """
    {
      "schemaVersion": 1,
      "projectRoots": ["\(projectsPath)"],
      "projectArtifacts": ["node_modules", ".build", "DerivedData"],
      "rules": [
        {
          "id": "vscode",
          "app": "Visual Studio Code",
          "appBundleID": "com.microsoft.VSCode",
          "requiresInstalled": true,
          "category": "appCaches",
          "risk": "safe",
          "why": "w",
          "paths": [{"base": "appSupport", "glob": "Code/CachedData"}]
        },
        {
          "id": "safari-privacy",
          "app": "Safari",
          "appBundleID": "com.apple.Safari",
          "requiresInstalled": false,
          "category": "browserPrivacy",
          "risk": "privacy",
          "why": "Contains browsing history and private data.",
          "paths": [{"base": "home", "glob": "Library/Safari/Fakedata"}]
        }
      ]
    }
    """
    return try! CatalogLoader.load(data: Data(s.utf8))
  }

  private func run(_ args: [String]) async -> (String, Int32) {
    await CLI.run(args: args, catalog: catalogJSON(),
                  inventory: AlwaysInstalled(), home: home,
                  mover: BinMover(bin: bin), storeURL: store)
  }

  // Default dry-run lists the safe item, does not trash anything.
  func test_dryRunListsButDoesNotTrash() async {
    let (out, code) = await run(["--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.contains("CachedData"))
    XCTAssertTrue(out.lowercased().contains("dry run"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: safeCacheURL.path))
  }

  // --clean (no --advanced) trashes ONLY the safe item; privacy item stays on disk.
  func test_cleanTrashesOnlySafeTierNotPrivacy() async {
    let (out, code) = await run(["--clean", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.lowercased().contains("trash"))
    // Safe cache should be moved.
    XCTAssertFalse(FileManager.default.fileExists(atPath: safeCacheURL.path),
                   "Safe-tier cache should have been trashed")
    // Privacy item must remain — CLI never trashes privacy tier.
    XCTAssertTrue(FileManager.default.fileExists(atPath: privacyURL.path),
                  "Privacy-tier item must NOT be trashed by --clean")
    // node_modules (rebuildable) must also remain without --advanced.
    XCTAssertTrue(FileManager.default.fileExists(atPath: nodeModulesURL.path),
                  "Rebuildable project artifact must NOT be trashed without --advanced")
  }

  // --clean --advanced trashes safe + rebuildable; still does NOT trash privacy.
  func test_cleanAdvancedTrashesRebuildableButNeverPrivacy() async {
    let (out, code) = await run(["--clean", "--advanced", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.lowercased().contains("trash"))
    // Safe cache should be gone.
    XCTAssertFalse(FileManager.default.fileExists(atPath: safeCacheURL.path),
                   "Safe-tier cache should have been trashed")
    // node_modules is rebuildable and should be trashed under --advanced.
    XCTAssertFalse(FileManager.default.fileExists(atPath: nodeModulesURL.path),
                   "Rebuildable project artifact should be trashed with --clean --advanced")
    // Privacy item must remain no matter what.
    XCTAssertTrue(FileManager.default.fileExists(atPath: privacyURL.path),
                  "Privacy-tier item must NEVER be trashed even with --clean --advanced")
  }

  // Project artifacts surface via --advanced (dry-run lists them, trashes nothing).
  func test_advancedListsProjectArtifacts() async {
    let (out, code) = await run(["--advanced", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.contains("node_modules"),
                  "--advanced must list project artifact directories")
    XCTAssertTrue(FileManager.default.fileExists(atPath: nodeModulesURL.path),
                  "--advanced without --clean must not trash anything")
  }

  // --json output is valid JSON with both candidates and reports keys.
  func test_jsonHasCandidatesAndReportsKeys() async throws {
    let (out, code) = await run(["--json"])
    XCTAssertEqual(code, 0)
    let obj = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
    )
    XCTAssertNotNil(obj["candidates"], "--json must include candidates key")
    XCTAssertNotNil(obj["reports"], "--json must include reports key")
    XCTAssertNotNil(obj["totalBytes"], "--json must include totalBytes key")
    let items = obj["candidates"] as? [[String: Any]]
    XCTAssertEqual(
      items?.first?["path"] as? String,
      safeCacheURL.path,
      "candidates[0].path must match the safe-tier cache URL"
    )
  }

  func test_cleanTrashesAndRecordsThenRestore() async {
    let (out, code) = await run(["--clean", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.lowercased().contains("trash"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: safeCacheURL.path))
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)

    let (rout, rcode) = await run(["--restore"])
    XCTAssertEqual(rcode, 0)
    XCTAssertTrue(rout.lowercased().contains("restore"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: safeCacheURL.path))
  }

  // --restore --json must emit JSON, not plain text, so piped consumers don't break.
  func test_restoreJSONEmitsValidJSON() async throws {
    _ = await run(["--clean", "--no-color"])

    let (out, code) = await run(["--restore", "--json"])
    XCTAssertEqual(code, 0)
    let obj = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
    )
    XCTAssertEqual(obj["failed"] as? Int, 0)
    XCTAssertGreaterThan(try XCTUnwrap(obj["restored"] as? Int), 0)

    let (eout, ecode) = await run(["--restore", "--json"])
    XCTAssertEqual(ecode, 0)
    let eobj = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(eout.utf8)) as? [String: Any],
      "empty-history restore must still be JSON under --json"
    )
    XCTAssertEqual(eobj["restored"] as? Int, 0)
  }

  // A restore where nothing comes back must be detectable by scripts.
  func test_restoreFailureExitsNonZero() async throws {
    let gone = TrashedItem(originalPath: home.appending(path: "gone").path,
                           trashedPath: bin.appending(path: "missing").path)
    try RestoreStore(storeURL: store)
      .record(CleanupBatch(id: "b1", date: Date(), items: [gone]))

    let (out, code) = await run(["--restore"])
    XCTAssertEqual(code, 1)
    XCTAssertTrue(out.contains("1 could not be restored"))
  }

  // History write failure must be surfaced, not silently lose the undo.
  func test_cleanWarnsWhenHistoryCannotBeSaved() async throws {
    // A file where the store's parent dir should be makes record() unwritable.
    let blocker = home.appending(path: "blocker")
    try Data().write(to: blocker)
    store = blocker.appending(path: "history.json")

    let (out, code) = await run(["--clean", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: safeCacheURL.path))
    XCTAssertTrue(out.lowercased().contains("history could not be saved"),
                  "record failure must produce a visible warning")
  }

  // JSON consumers must see the lost-undo warning too, not just text-mode users.
  func test_jsonCleanCarriesHistoryWarning() async throws {
    let blocker = home.appending(path: "blocker")
    try Data().write(to: blocker)
    store = blocker.appending(path: "history.json")

    let (out, code) = await run(["--clean", "--json"])
    XCTAssertEqual(code, 0)
    let obj = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
    )
    XCTAssertTrue((obj["warning"] as? String ?? "").lowercased()
                    .contains("history could not be saved"),
                  "--json --clean must carry the record-failure warning")
  }

  func test_noColorHasNoAnsiEscapes() async {
    let (out, _) = await run(["--list", "--no-color"])
    XCTAssertFalse(out.contains("\u{1B}["))
  }
}

struct AlwaysInstalled: AppInventory {
  func isInstalled(bundleID: String) -> Bool { true }
  // Installed apps contribute name tokens, so their Library dirs aren't flagged as orphans.
  func knownSet() -> Set<String> { ["code"] }
}
struct BinMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let d = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: d); return d
  }
}
