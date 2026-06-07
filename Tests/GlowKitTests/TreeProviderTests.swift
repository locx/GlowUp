import XCTest
@testable import GlowKit

final class TreeProviderTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-tree-\(UUID().uuidString)")
    try mk("Library/Caches/App/sub")
    try Data("x".utf8).write(to: home.appending(path: "Library/Caches/App/file.txt"))
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }
  private func mk(_ rel: String) throws {
    try FileManager.default.createDirectory(
      at: home.appending(path: rel), withIntermediateDirectories: true)
  }

  func test_listsImmediateChildrenWithDirFlag() {
    let dir = home.appending(path: "Library/Caches/App")
    let nodes = TreeProvider.children(of: dir, home: home)
    let byName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })
    XCTAssertEqual(Set(byName.keys), ["sub", "file.txt"])
    XCTAssertTrue(byName["sub"]!.isDirectory)
    XCTAssertFalse(byName["file.txt"]!.isDirectory)
  }

  func test_excludesVetoedChildren() throws {
    // A child that resolves to a protected location must not appear.
    try mk("Documents")
    let link = home.appending(path: "Library/Caches/App/docs")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: home.appending(path: "Documents"))
    let dir = home.appending(path: "Library/Caches/App")
    let names = TreeProvider.children(of: dir, home: home).map(\.name)
    XCTAssertFalse(names.contains("docs"))
  }
}
