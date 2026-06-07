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
}

// Test double used here and by ScannerTests.
struct FakeInventory: AppInventory {
  let installed: Set<String>
  func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}
