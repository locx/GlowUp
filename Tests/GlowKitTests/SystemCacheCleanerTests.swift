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
}
