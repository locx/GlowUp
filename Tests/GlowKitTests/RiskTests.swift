import XCTest
@testable import GlowKit

final class RiskTests: XCTestCase {
  func test_decodesFromLowercaseString() throws {
    let data = Data("\"stateful\"".utf8)
    XCTAssertEqual(try JSONDecoder().decode(Risk.self, from: data), .stateful)
  }

  func test_safeIsDefaultSelectable() {
    XCTAssertEqual(Risk.allCases.filter { $0.isDefaultSelected }, [.safe])
  }
}
