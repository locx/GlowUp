import XCTest
@testable import GlowKit

final class ResolverTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glowkit-\(UUID().uuidString)")
    try mk("Library/Caches/Code/CachedData")
    try mk("Library/Application Support/Brave/Default/Cache")
    try mk("Library/Application Support/Brave/Profile 1/Cache")
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  func test_resolvesExactPath() {
    let spec = PathSpec(base: .caches, glob: "Code/CachedData")
    let urls = Resolver.resolve(spec, home: home)
    XCTAssertEqual(urls.map(\.lastPathComponent), ["CachedData"])
  }

  func test_resolvesProfileGlobAcrossProfiles() {
    let spec = PathSpec(base: .appSupport, glob: "Brave/*/Cache")
    let names = Set(Resolver.resolve(spec, home: home).map { $0.path })
    XCTAssertEqual(names.count, 2)   // Default + Profile 1
  }

  func test_skipsNonexistentPaths() {
    let spec = PathSpec(base: .caches, glob: "DoesNotExist")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }

  func test_neverReturnsVetoedPaths() throws {
    try mk("Documents/Code")   // would match the glob shape but is protected
    let spec = PathSpec(base: .home, glob: "Documents/Code")
    XCTAssertTrue(Resolver.resolve(spec, home: home).isEmpty)
  }
}
