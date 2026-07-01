import XCTest
@testable import GlowUpUI

final class AppLinksTests: XCTestCase {
  func test_externalLinksAreWellFormed() {
    XCTAssertEqual(AppLinks.gitHub?.absoluteString, "https://github.com/locx/GlowUp")
    XCTAssertEqual(AppLinks.fullDiskAccessSettings?.scheme, "x-apple.systempreferences")
  }
}
