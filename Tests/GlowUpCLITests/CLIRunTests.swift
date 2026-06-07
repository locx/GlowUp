import XCTest
import GlowKit
@testable import GlowUpCLI

final class CLIRunTests: XCTestCase {
  private var home: URL!
  private var store: URL!
  private var bin: URL!

  override func setUpWithError() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-cli-\(UUID().uuidString)")
    home = root.appending(path: "home")
    store = root.appending(path: "history.json")
    bin = root.appending(path: "bin")
    let fm = FileManager.default
    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    try fm.createDirectory(
      at: home.appending(path: "Library/Application Support/Code/CachedData"),
      withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(
      to: home.appending(path: "Library/Application Support/Code/CachedData/x"))
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
  }

  private func catalogJSON() -> Catalog {
    let s = #"{"schemaVersion":1,"projectRoots":[],"projectArtifacts":[],"rules":[{"id":"vscode","app":"Visual Studio Code","appBundleID":"com.microsoft.VSCode","requiresInstalled":true,"category":"appCaches","risk":"safe","why":"w","paths":[{"base":"appSupport","glob":"Code/CachedData"}]}]}"#
    return try! CatalogLoader.load(data: Data(s.utf8))
  }

  private func run(_ args: [String]) async -> (String, Int32) {
    await CLI.run(args: args, catalog: catalogJSON(),
                  inventory: AlwaysInstalled(), home: home,
                  mover: BinMover(bin: bin), storeURL: store)
  }

  func test_dryRunListsButDoesNotTrash() async {
    let (out, code) = await run(["--no-color"])     // default dry-run
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.contains("CachedData"))
    XCTAssertTrue(out.lowercased().contains("dry run"))
    XCTAssertTrue(FileManager.default.fileExists(   // nothing moved
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
  }

  func test_jsonIsValidAndSchemaConformant() async throws {
    let (out, code) = await run(["--json"])
    XCTAssertEqual(code, 0)
    let obj = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
    XCTAssertNotNil(obj?["totalBytes"])
    let items = obj?["candidates"] as? [[String: Any]]
    XCTAssertEqual(items?.first?["path"] as? String,
                   home.appending(path: "Library/Application Support/Code/CachedData").path)
  }

  func test_cleanTrashesAndRecordsThenRestore() async {
    let (out, code) = await run(["--clean", "--no-color"])
    XCTAssertEqual(code, 0)
    XCTAssertTrue(out.lowercased().contains("trash"))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
    XCTAssertEqual(RestoreStore(storeURL: store).batches().count, 1)

    let (rout, rcode) = await run(["--restore"])
    XCTAssertEqual(rcode, 0)
    XCTAssertTrue(rout.lowercased().contains("restore"))
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: home.appending(path: "Library/Application Support/Code/CachedData").path))
  }

  func test_noColorHasNoAnsiEscapes() async {
    let (out, _) = await run(["--list", "--no-color"])
    XCTAssertFalse(out.contains("\u{1B}["))
  }

  func test_projectsModeIsHonestlyDeferred() async {
    let (out, code) = await run(["--projects"])
    XCTAssertNotEqual(code, 0)
    XCTAssertTrue(out.lowercased().contains("advanced"))
  }
}

struct AlwaysInstalled: AppInventory { func isInstalled(bundleID: String) -> Bool { true } }
struct BinMover: ItemMover {
  let bin: URL
  func trash(_ url: URL) throws -> URL {
    let d = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: d); return d
  }
}
