import XCTest
@testable import GlowKit

final class SystemCacheCleanerTests: XCTestCase {
  private final class FakeRunner: RootCommandRunner, @unchecked Sendable {
    var received: String?
    func runAsRoot(_ command: String) -> Bool { received = command; return true }
  }

  func test_removalCommandRejectsEmpty() {
    XCTAssertNil(SystemCacheCleaner.removalCommand([]))
  }

  func test_removalCommandRejectsOutOfScope() {
    let bad = [
      "/etc/passwd", "/Library/Caches", "/Library/Caches/foo/bar",
      "/Library/Application Support/x", "/",
    ].map { URL(fileURLWithPath: $0) }
    for u in bad {
      XCTAssertNil(SystemCacheCleaner.removalCommand([u]), "must refuse \(u.path)")
    }
  }

  func test_removalCommandQuotesDirectChildren() {
    let cmd = SystemCacheCleaner.removalCommand([
      URL(fileURLWithPath: "/Library/Caches/com.foo"),
      URL(fileURLWithPath: "/Library/Caches/with space"),
    ])
    XCTAssertEqual(cmd, "/bin/rm -rf '/Library/Caches/com.foo' '/Library/Caches/with space'")
  }

  func test_removalCommandRejectsDotDotEscapingScope() {
    // `..` that standardizes outside /Library/Caches must be refused.
    let bad = [
      "/Library/Caches/../etc",
      "/Library/Caches/foo/../../etc",
    ].map { URL(fileURLWithPath: $0, isDirectory: false) }
    for u in bad {
      XCTAssertNil(SystemCacheCleaner.removalCommand([u]), "must refuse \(u.path)")
    }
  }

  func test_removalCommandShellEscapesSingleQuote() {
    let cmd = SystemCacheCleaner.removalCommand([
      URL(fileURLWithPath: "/Library/Caches/o'brien"),
    ])
    XCTAssertEqual(cmd, "/bin/rm -rf '/Library/Caches/o'\\''brien'")
  }

  func test_cleanRefusesOutOfScopeWithoutRunning() {
    let r = FakeRunner()
    XCTAssertFalse(SystemCacheCleaner.clean([URL(fileURLWithPath: "/etc")], runner: r))
    XCTAssertNil(r.received, "runner must not fire for an out-of-scope path")
  }

  func test_cleanRunsForValidScope() {
    let r = FakeRunner()
    XCTAssertTrue(SystemCacheCleaner.clean([URL(fileURLWithPath: "/Library/Caches/com.foo")], runner: r))
    XCTAssertEqual(r.received, "/bin/rm -rf '/Library/Caches/com.foo'")
  }

  func test_removalCommandRejectsSymlinkResolvingOutsideScope() throws {
    // A direct-child symlink whose target leaves /Library/Caches must be refused: the
    // scope check resolves symlinks, so the link's own direct-child path can't smuggle it through.
    let root = "/Library/Caches"
    guard FileManager.default.isWritableFile(atPath: root) else {
      throw XCTSkip("\(root) not writable; cannot plant a symlink fixture")
    }
    let link = URL(fileURLWithPath: root).appending(path: "glowtest-link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
    defer { try? FileManager.default.removeItem(at: link) }
    XCTAssertNil(SystemCacheCleaner.removalCommand([link]),
                 "a direct child resolving outside /Library/Caches must be refused")
  }
}
