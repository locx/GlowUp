import XCTest
@testable import GlowKit

final class ResolverTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glowkit-\(UUID().uuidString)")
    try mk("Library/Caches/Code/CachedData")
    try mk("Library/Application Support/Brave/Default/Cache")
    try mk("Library/Application Support/Brave/Profile 1/Cache")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  func test_resolvesExactPath() {
    let spec = PathSpec(base: .caches, glob: "Code/CachedData")
    let urls = Resolver.resolve(spec, home: home)
    XCTAssertEqual(urls.map(\.lastPathComponent), ["CachedData"])
  }

  func test_resolvesProfileGlobAcrossProfiles() {
    let spec = PathSpec(base: .appSupport, glob: "Brave/*/Cache")
    let names = Set(Resolver.resolve(spec, home: home).map { $0.path })
    XCTAssertEqual(names.count, 2)   // Default + Profile 1
  }

  func test_skipsNonexistentPaths() {
    let spec = PathSpec(base: .caches, glob: "DoesNotExist")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }

  func test_neverReturnsVetoedPaths() throws {
    try mk("Documents/Code")   // would match the glob shape but is protected
    let spec = PathSpec(base: .home, glob: "Documents/Code")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }

  // A read the scan can't perform must surface, not vanish — an unreadable dir a `*` enumerates into
  // is recorded so a permission-denied scan can't masquerade as "nothing to clean".
  func test_unreadableWildcardDirRecordsDiagnostic() throws {
    try XCTSkipIf(getuid() == 0, "root bypasses directory permissions")
    let sub = home.appending(path: "Library/Caches/Locked")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sub.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub.path) }

    let diagnostics = ScanDiagnostics()
    let spec = PathSpec(base: .caches, glob: "Locked/*")
    _ = Resolver.resolve(spec, home: home, diagnostics: diagnostics)
    XCTAssertTrue(diagnostics.failedDirectories.contains { $0.path == sub.path },
                  "unreadable dir not recorded: \(diagnostics.failedDirectories)")
  }

  // Resolved URLs must never escape the base root nor contain "..", for any child name on disk —
  // including names with "*", spaces, dots, and unicode. Seeded by index so runs are reproducible.
  func test_fuzz_resolvedURLsNeverEscapeBaseRoot() throws {
    let alphabet: [String] = [
      "a", "b", "Cache", "Code Cache", "*", "**", ".", "..", "...", "....",
      " ", "  ", ".hidden", "name.with.dots", "ünïcödé", "日本語", "café",
      "a*b", "*.tmp", "x/y", "..*", "*..", "n a m e", "\u{200B}", "—dash"
    ]
    let bases: [BaseRoot] = BaseRoot.allCases
    let globs = ["*", "*/Cache", "Sub/*", "*/*", "Code/*"]

    for index in 0..<1200 {
      var rng = SeededRNG(seed: UInt64(index) &* 2_654_435_761 &+ 1)
      let base = bases[Int(rng.next() % UInt64(bases.count))]
      let glob = globs[Int(rng.next() % UInt64(globs.count))]

      // Plant 1–3 child dirs with adversarial names under the chosen base root.
      let baseURL = base.url(home: home)
      let count = 1 + Int(rng.next() % 3)
      for _ in 0..<count {
        let depth = 1 + Int(rng.next() % 2)
        var rel = ""
        for _ in 0..<depth {
          let seg = alphabet[Int(rng.next() % UInt64(alphabet.count))]
          rel += rel.isEmpty ? seg : "/\(seg)"
        }
        // FileManager rejects empty/"."/".." path components; tolerate any failure and move on.
        try? FileManager.default.createDirectory(
          at: baseURL.appending(path: rel), withIntermediateDirectories: true)
      }

      let spec = PathSpec(base: base, glob: glob)
      let resolvedRoot = baseURL.resolvingSymlinksInPath().path
      for url in Resolver.resolve(spec, home: home) {
        let p = url.resolvingSymlinksInPath().path
        // RED-TEAM INVARIANT: never weaken these — a failure here is a real Resolver escape bug.
        XCTAssertFalse(url.pathComponents.contains(".."),
                       "resolved URL contains '..': \(url.path) [base=\(base) glob=\(glob)]")
        XCTAssertTrue(p == resolvedRoot || p.hasPrefix(resolvedRoot + "/"),
                      "resolved URL escaped base root \(resolvedRoot): \(p) [glob=\(glob)]")
      }
    }
  }

  // Same no-escape/no-".." invariants, but over globs of the shape CatalogLoader actually accepts
  // (literal first segment, wildcards only in later segments) — the previous set is unreachable in
  // production. Asserts the Resolver doesn't escape even for the globs it really faces.
  func test_fuzz_productionGlobShapesNeverEscapeBaseRoot() throws {
    let alphabet: [String] = [
      "App", "Sub", "Data", "Cache", "Specific", "Name", "Code Cache", "*",
      ".", "..", "...", " ", ".hidden", "name.with.dots", "ünïcödé", "café",
      "a*b", "*.tmp", "..*", "*..", "n a m e", "—dash"
    ]
    let bases: [BaseRoot] = BaseRoot.allCases
    // Valid production shapes: first segment is always literal (no leading wildcard, no "**", no "..").
    let globs = ["App/*/Cache", "App/Sub/Data", "Specific/Name", "App/*", "App/Sub/*/Data"]

    for index in 0..<1200 {
      var rng = SeededRNG(seed: UInt64(index) &* 2_654_435_761 &+ 7)
      let base = bases[Int(rng.next() % UInt64(bases.count))]
      let glob = globs[Int(rng.next() % UInt64(globs.count))]
      let baseURL = base.url(home: home)

      // Plant 1–3 dirs whose first component is the glob's literal first segment, with adversarial
      // names filling the wildcard positions, so the resolver has real entries to expand.
      let firstSeg = String(glob.split(separator: "/").first ?? "App")
      let count = 1 + Int(rng.next() % 3)
      for _ in 0..<count {
        let depth = 1 + Int(rng.next() % 3)
        var rel = firstSeg
        for _ in 0..<depth {
          let seg = alphabet[Int(rng.next() % UInt64(alphabet.count))]
          rel += "/\(seg)"
        }
        try? FileManager.default.createDirectory(
          at: baseURL.appending(path: rel), withIntermediateDirectories: true)
      }

      let spec = PathSpec(base: base, glob: glob)
      let resolvedRoot = baseURL.resolvingSymlinksInPath().path
      for url in Resolver.resolve(spec, home: home) {
        let p = url.resolvingSymlinksInPath().path
        XCTAssertFalse(url.pathComponents.contains(".."),
                       "resolved URL contains '..': \(url.path) [base=\(base) glob=\(glob)]")
        XCTAssertTrue(p == resolvedRoot || p.hasPrefix(resolvedRoot + "/"),
                      "resolved URL escaped base root \(resolvedRoot): \(p) [glob=\(glob)]")
      }
    }
  }
}

// Deterministic SplitMix64 so the fuzz is reproducible and CI-stable (no Date/arc4random).
private struct SeededRNG {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
