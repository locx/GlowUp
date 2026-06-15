import XCTest
@testable import GlowKit

final class InventoryTests: XCTestCase {
  func test_fakeInventoryReportsConfiguredBundleIDs() {
    let inv = FakeInventory(installed: ["com.microsoft.VSCode"])
    XCTAssertTrue(inv.isInstalled(bundleID: "com.microsoft.VSCode"))
    XCTAssertFalse(inv.isInstalled(bundleID: "com.unknown.App"))
  }

  func test_systemInventoryDoesNotCrashForUnknownBundleID() {
    // Real lookup of a bundle ID that cannot exist must return false, not throw.
    XCTAssertFalse(SystemInventory().isInstalled(bundleID: "com.glowup.definitely.not.real"))
  }

  func test_knownSetIsComputedOncePerInstance() {
    // A second scan in the same session must reuse the cache, not redo the /Applications walk.
    let count = Counter()
    let inv = SystemInventory(knownSetProducer: { count.bump(); return ["x"] })
    XCTAssertEqual(inv.knownSet(), ["x"])
    XCTAssertEqual(inv.knownSet(), ["x"])
    XCTAssertEqual(count.value, 1, "the expensive producer must run only once")
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  func bump() { lock.lock(); n += 1; lock.unlock() }
  var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

// Test double used here and by ScannerTests.
struct FakeInventory: AppInventory {
  let installed: Set<String>
  func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}
