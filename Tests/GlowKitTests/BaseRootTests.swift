import XCTest
@testable import GlowKit

final class BaseRootTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/Users/test")

  func test_resolvesAppSupport() {
    XCTAssertEqual(BaseRoot.appSupport.url(home: home).path,
                   "/Users/test/Library/Application Support")
  }

  func test_resolvesCachesAndHome() {
    XCTAssertEqual(BaseRoot.caches.url(home: home).path,
                   "/Users/test/Library/Caches")
    XCTAssertEqual(BaseRoot.home.url(home: home).path, "/Users/test")
  }

  func test_decodesFromString() throws {
    let data = Data("\"logs\"".utf8)
    XCTAssertEqual(try JSONDecoder().decode(BaseRoot.self, from: data), .logs)
  }
}
