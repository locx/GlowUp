import XCTest
@testable import GlowUpCLI

final class CLIOptionsTests: XCTestCase {
  func test_defaultsToDryRun() {
    let o = CLIOptions.parse([])
    XCTAssertEqual(o.mode, .dryRun)
    XCTAssertFalse(o.advanced)
    XCTAssertFalse(o.json)
    XCTAssertFalse(o.noColor)
  }

  func test_parsesModesAndFlags() {
    XCTAssertEqual(CLIOptions.parse(["--list"]).mode, .list)
    XCTAssertEqual(CLIOptions.parse(["--clean"]).mode, .clean)
    XCTAssertEqual(CLIOptions.parse(["--restore"]).mode, .restore)
    XCTAssertEqual(CLIOptions.parse(["--projects"]).mode, .projects)
    let o = CLIOptions.parse(["--clean", "--advanced", "--json", "--no-color"])
    XCTAssertEqual(o.mode, .clean)
    XCTAssertTrue(o.advanced)
    XCTAssertTrue(o.json)
    XCTAssertTrue(o.noColor)
  }

  func test_unknownFlagIsRecorded() {
    XCTAssertEqual(CLIOptions.parse(["--bogus"]).unknown, ["--bogus"])
  }
}
