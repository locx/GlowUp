import XCTest
@testable import GlowKit

final class SimulatorCleanerTests: XCTestCase {
  private final class FakeRunner: ShellRunner, @unchecked Sendable {
    var launchPath: String?
    var args: [String]?
    var stdout: String?
    func run(_ launchPath: String, _ args: [String]) -> Bool {
      self.launchPath = launchPath; self.args = args; return true
    }
    func output(_ launchPath: String, _ args: [String]) -> String? {
      self.launchPath = launchPath; self.args = args; return stdout
    }
  }

  func test_deleteUnavailableInvokesSimctl() {
    let r = FakeRunner()
    XCTAssertTrue(SimulatorCleaner.deleteUnavailable(runner: r))
    XCTAssertEqual(r.launchPath, "/usr/bin/xcrun")
    XCTAssertEqual(r.args, ["simctl", "delete", "unavailable"])
  }

  func test_hasUnavailableTrueWhenListReportsUnavailable() {
    let r = FakeRunner()
    r.stdout = "-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-16-0 --\n    iPhone 14 (unavailable, runtime profile not found)\n"
    XCTAssertTrue(SimulatorCleaner.hasUnavailable(runner: r))
    XCTAssertEqual(r.args, ["simctl", "list", "devices"])
  }

  func test_hasUnavailableFalseWhenAllAvailable() {
    let r = FakeRunner()
    r.stdout = "-- iOS 17.0 --\n    iPhone 15 (UUID) (Shutdown)\n"
    XCTAssertFalse(SimulatorCleaner.hasUnavailable(runner: r))
  }
}
