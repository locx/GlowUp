import XCTest
@testable import GlowKit

final class WorkspaceStorageScannerTests: XCTestCase {
  private var home: URL!
  private var storage: URL!

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-ws-\(UUID().uuidString)")
    storage = home.appending(path: "Library/Application Support/Code/User/workspaceStorage")
    try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

  private func entry(_ id: String, folder: URL) throws {
    let dir = storage.appending(path: id)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"folder":"\#(folder.absoluteString)"}"#
    try Data(json.utf8).write(to: dir.appending(path: "workspace.json"))
  }

  func test_flagsOnlyDanglingWorkspaces() throws {
    let live = home.appending(path: "projects/live")
    try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
    try entry("aaa", folder: live)                                   // exists
    try entry("bbb", folder: home.appending(path: "projects/gone")) // missing

    let found = WorkspaceStorageScanner.scan(home: home)
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["bbb"])
    XCTAssertEqual(found.first?.category, "workspaceOrphans")
    // Workspace storage holds extension state, never one default click from the Trash.
    XCTAssertEqual(found.first?.risk, .rebuildable)
  }

  // Older VSCode builds wrote raw POSIX paths instead of file:// URIs.
  func test_flagsDanglingRawPathWorkspaces() throws {
    let dir = storage.appending(path: "raw")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"folder":"\#(home.appending(path: "projects/gone-raw").path)"}"#
    try Data(json.utf8).write(to: dir.appending(path: "workspace.json"))

    let found = WorkspaceStorageScanner.scan(home: home)
    XCTAssertEqual(found.map(\.url.lastPathComponent), ["raw"])
  }

  // Remote workspaces can't be verified gone from this machine — never flagged.
  func test_skipsRemoteWorkspaces() throws {
    let dir = storage.appending(path: "remote")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"folder":"vscode-remote://ssh-remote%2Bhost/work/app"}"#
    try Data(json.utf8).write(to: dir.appending(path: "workspace.json"))

    XCTAssertTrue(WorkspaceStorageScanner.scan(home: home).isEmpty)
  }
}
