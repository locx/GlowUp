import XCTest
@testable import GlowKit

final class SizeMeasurerTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-size-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root.appending(path: "sub"), withIntermediateDirectories: true)
    try Data(repeating: 0xAB, count: 4096).write(to: root.appending(path: "a.bin"))
    try Data(repeating: 0xCD, count: 4096).write(to: root.appending(path: "sub/b.bin"))
  }
  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func test_measuresDirectoryTreeBytes() async {
    let bytes = await SizeMeasurer.size(of: root)
    XCTAssertGreaterThanOrEqual(bytes, 8192)   // two 4 KiB files, allocated
  }

  func test_measuresSingleFile() async {
    let bytes = await SizeMeasurer.size(of: root.appending(path: "a.bin"))
    XCTAssertGreaterThanOrEqual(bytes, 4096)
  }

  func test_missingPathIsZero() async {
    let bytes = await SizeMeasurer.size(of: root.appending(path: "nope"))
    XCTAssertEqual(bytes, 0)
  }

  func test_measureManyReturnsPerURLSizes() async {
    let urls = [root.appending(path: "a.bin"), root.appending(path: "sub/b.bin")]
    let sizes = await SizeMeasurer.measure(urls)
    XCTAssertEqual(sizes.count, 2)
    XCTAssertGreaterThanOrEqual(sizes[urls[0]] ?? 0, 4096)
    XCTAssertGreaterThanOrEqual(sizes[urls[1]] ?? 0, 4096)
  }

  func test_measureManyUnderLoadKeepsEveryResult() async throws {
    let fm = FileManager.default
    let load = root.appending(path: "load")
    try fm.createDirectory(at: load, withIntermediateDirectories: true)
    // More inputs than the in-flight window, so completions must re-seed the group.
    var urls: [URL] = []
    for i in 0..<64 {
      let url = load.appending(path: "f\(i).bin")
      try Data(repeating: 0xEF, count: 4096).write(to: url)
      urls.append(url)
    }
    let sizes = await SizeMeasurer.measure(urls)
    XCTAssertEqual(sizes.count, urls.count)
    for url in urls {
      XCTAssertGreaterThanOrEqual(sizes[url] ?? 0, 4096)
    }
  }
}
