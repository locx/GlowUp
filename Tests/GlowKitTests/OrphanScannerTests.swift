import XCTest
@testable import GlowKit

final class OrphanScannerTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-orphan-\(UUID().uuidString)")

    // Known app — kept via known-set match.
    try mkdir("Library/Application Support/KnownApp")
    // Orphan — no owning app.
    try mkdir("Library/Application Support/OldLeftover")
    // KEEP prefix — always kept.
    try mkdir("Library/Caches/com.apple.Something")
    // Dotfile — always skipped.
    try mkdir("Library/Application Support/.hidden-thing")
    // Symlink in App Support — must be skipped.
    // Real target lives outside Library so it is not itself scanned.
    let realTarget = home.appending(path: "_symlink_real_target")
    try mkdir("_symlink_real_target")
    try FileManager.default.createSymbolicLink(
      at: home.appending(path: "Library/Application Support/SymLinkedDir"),
      withDestinationURL: realTarget)

    // Container with a matching LaunchAgent plist — should be demoted.
    try mkdir("Library/Containers/com.acme.helper")
    try mkdir("Library/LaunchAgents")
    let plistURL = home.appending(path: "Library/LaunchAgents/com.acme.helper.plist")
    let plistData: NSDictionary = ["Label": "com.acme.helper"]
    plistData.write(to: plistURL, atomically: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  // Convenience.
  private func mkdir(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  /// Only the entry with no known match must be flagged.
  func test_flagsUnknownEntriesOnly() {
    let found = OrphanScanner.scan(home: home, known: ["knownapp"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertEqual(names, ["OldLeftover"],
                   "Expected only OldLeftover; got \(names)")
    XCTAssertEqual(found.first?.category, "libraryOrphans")
    // Heuristic orphans are persistent app data, never one default click from the Trash.
    XCTAssertEqual(found.first?.risk, .rebuildable)
  }

  /// When every entry is covered by the known set, nothing is flagged.
  func test_returnsEmptyWhenAllKnown() {
    let found = OrphanScanner.scan(
      home: home,
      known: ["knownapp", "oldleftover", "com.known.app"])
    XCTAssertTrue(found.isEmpty, "Expected empty; got \(found.map(\.url.lastPathComponent))")
  }

  /// Dotfiles must never appear in results regardless of known set.
  func test_dotfilesAreAlwaysSkipped() {
    let found = OrphanScanner.scan(home: home, known: ["knownapp"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertFalse(names.contains(where: { $0.hasPrefix(".") }),
                   "Dotfile leaked into results: \(names)")
  }

  /// Symlinks in App Support must be silently skipped.
  func test_symlinksAreSkipped() {
    let found = OrphanScanner.scan(home: home, known: ["knownapp"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertFalse(names.contains("SymLinkedDir"),
                   "Symlink leaked into results: \(names)")
  }

  /// com.apple.* and other KEEP-prefixed entries must never be flagged.
  func test_keepPrefixEntriesAreNeverFlagged() {
    let found = OrphanScanner.scan(home: home, known: ["knownapp"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertFalse(names.contains("com.apple.Something"),
                   "KEEP-prefix entry appeared in orphans: \(names)")
  }

  /// A Container whose ID appears as the Label in a LaunchAgent plist must be demoted.
  func test_containerReferencedByLaunchAgentIsDemoted() {
    let found = OrphanScanner.scan(home: home, known: ["knownapp"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertFalse(names.contains("com.acme.helper"),
                   "Launchd-referenced container was not demoted: \(names)")
  }

  /// Caches/Logs are owned by GenericCacheScanner; orphans there must not be double-emitted.
  func test_doesNotScanCacheOrLogRoots() throws {
    try mkdir("Library/Caches/leftover.app")
    try mkdir("Library/Logs/leftover.app")
    let names = OrphanScanner.scan(home: home, known: ["knownapp"]).map(\.url.path)
    XCTAssertFalse(names.contains { $0.contains("Library/Caches/") || $0.contains("Library/Logs/") })
  }

  /// A known token >= 6 chars must cause a substring match (e.g. "google" keeps "Google").
  func test_knownTokenSubstringKeepsEntry() throws {
    try mkdir("Library/Application Support/Google")
    let found = OrphanScanner.scan(home: home, known: ["knownapp", "google"])
    let names = found.map(\.url.lastPathComponent)
    XCTAssertFalse(names.contains("Google"),
                   "Token-matched entry 'Google' should have been kept; got \(names)")
  }
}
