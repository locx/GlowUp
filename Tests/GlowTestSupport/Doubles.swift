import Foundation
import GlowKit

// Shared test doubles. Only the public GlowKit protocols are used, so this builds without @testable.

// Moves into a temp bin instead of the real Trash; UUID-prefixed so distinct sources never collide.
public struct BinMover: ItemMover {
  let bin: URL
  public init(bin: URL) { self.bin = bin }
  public func trash(_ url: URL) throws -> URL {
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}

// Like BinMover but throws for one path component, to exercise partial-failure recording.
public struct PartialMover: ItemMover {
  let bin: URL
  let failingComponent: String
  struct FakeError: Error {}
  public init(bin: URL, failingComponent: String = "Cache2") {
    self.bin = bin; self.failingComponent = failingComponent
  }
  public func trash(_ url: URL) throws -> URL {
    if url.lastPathComponent == failingComponent { throw FakeError() }
    let dest = bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    try FileManager.default.moveItem(at: url, to: dest)
    return dest
  }
}

// Configurable inventory: an app is installed iff its id is listed; knownSet returns `known`.
public struct FakeInventory: AppInventory {
  let installed: Set<String>
  let known: Set<String>
  public init(installed: Set<String> = [], known: Set<String> = []) {
    self.installed = installed; self.known = known
  }
  public func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
  public func knownSet() -> Set<String> { known }
}

// Treats every app as installed; the ["code"] token keeps VSCode's Library dirs off the orphan list.
public struct InstalledInventory: AppInventory {
  public init() {}
  public func isInstalled(bundleID: String) -> Bool { true }
  public func knownSet() -> Set<String> { ["code"] }
}

// Records whether the permanent root op was reached, so a test can prove the default path avoids it.
public final class SpyRoot: RootCommandRunner, @unchecked Sendable {
  public private(set) var fired = false
  public init() {}
  public func runAsRoot(_ command: String) -> Bool { fired = true; return true }
}

// Records whether the permanent simctl op was reached.
public final class SpyShell: ShellRunner, @unchecked Sendable {
  public private(set) var fired = false
  public init() {}
  public func run(_ launchPath: String, _ args: [String]) -> Bool { fired = true; return true }
}
