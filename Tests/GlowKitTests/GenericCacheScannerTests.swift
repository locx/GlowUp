import XCTest
@testable import GlowKit

final class GenericCacheScannerTests: XCTestCase {
  private func tmpHome() throws -> URL {
    let h = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-gcache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: h.appending(path: "Library/Caches"), withIntermediateDirectories: true)
    return h
  }

  func test_emitsPlainCacheDirAsRebuildable() throws {
    let home = try tmpHome(); defer { try? FileManager.default.removeItem(at: home) }
    let caches = home.appending(path: "Library/Caches")
    try FileManager.default.createDirectory(
      at: caches.appending(path: "com.example.app"), withIntermediateDirectories: true)
    try Data().write(to: caches.appending(path: "com.example.app/blob"))
    let out = GenericCacheScanner.scan(home: home)
    XCTAssertTrue(out.contains { $0.url.lastPathComponent == "com.example.app" && $0.risk == .rebuildable })
  }

  func test_sweepsContainerAndGroupContainerCaches() throws {
    let home = try tmpHome(); defer { try? FileManager.default.removeItem(at: home) }
    let fm = FileManager.default
    try fm.createDirectory(
      at: home.appending(path: "Library/Containers/com.app/Data/Library/Caches/x"),
      withIntermediateDirectories: true)
    try fm.createDirectory(
      at: home.appending(path: "Library/Group Containers/group.app/Library/Caches/y"),
      withIntermediateDirectories: true)
    let out = GenericCacheScanner.scan(home: home)
    XCTAssertTrue(out.contains { $0.url.path.hasSuffix("Containers/com.app/Data/Library/Caches") })
    XCTAssertTrue(out.contains { $0.url.path.hasSuffix("Group Containers/group.app/Library/Caches") })
  }

  func test_sweepsLibraryLogsAsSystemLogs() throws {
    let home = try tmpHome(); defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
      at: home.appending(path: "Library/Logs/SomeApp"), withIntermediateDirectories: true)
    let out = GenericCacheScanner.scan(home: home)
    XCTAssertTrue(out.contains { $0.url.lastPathComponent == "SomeApp" && $0.category == "systemLogs" })
  }

  func test_skipsSymlink() throws {
    let home = try tmpHome(); defer { try? FileManager.default.removeItem(at: home) }
    let caches = home.appending(path: "Library/Caches")
    let target = caches.appending(path: "real")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: caches.appending(path: "link"), withDestinationURL: target)
    let out = GenericCacheScanner.scan(home: home)
    XCTAssertFalse(out.contains { $0.url.lastPathComponent == "link" })
  }
}
