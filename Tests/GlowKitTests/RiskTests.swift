import XCTest
@testable import GlowKit

final class RiskTests: XCTestCase {
  func test_decodesFromLowercaseString() throws {
    let data = Data("\"stateful\"".utf8)
    XCTAssertEqual(try JSONDecoder().decode(Risk.self, from: data), .stateful)
  }

  func test_defaultSelectableTiers() {
    XCTAssertEqual(Risk.defaultSelectable, [.safe, .rebuildable])
    XCTAssertEqual(Risk.cleanTiers(advanced: false), [.safe])
    XCTAssertEqual(Risk.scanTiers(advanced: false), [.safe])
    XCTAssertEqual(Risk.scanTiers(advanced: true), Set(Risk.allCases))
  }
}
