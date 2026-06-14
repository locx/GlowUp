import XCTest
@testable import GlowKit

final class SimulatorCleanerTests: XCTestCase {
  private final class FakeRunner: ShellRunner, @unchecked Sendable {
    var launchPath: String?
    var args: [String]?
    func run(_ launchPath: String, _ args: [String]) -> Bool {
      self.launchPath = launchPath; self.args = args; return true
    }
  }

  func test_deleteUnavailableInvokesSimctl() {
    let r = FakeRunner()
    XCTAssertTrue(SimulatorCleaner.deleteUnavailable(runner: r))
    XCTAssertEqual(r.launchPath, "/usr/bin/xcrun")
    XCTAssertEqual(r.args, ["simctl", "delete", "unavailable"])
  }
}
