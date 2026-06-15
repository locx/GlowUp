import Foundation

// Records dirs a scan couldn't read so a permission-denied discovery isn't mistaken for "nothing to clean".
public final class ScanDiagnostics: @unchecked Sendable {
  // Crosses into a background Task, so reads and writes are lock-guarded.
  private let lock = NSLock()
  private var failed: [URL] = []

  public init() {}

  public func recordFailure(_ dir: URL) {
    lock.lock()
    defer { lock.unlock() }
    failed.append(dir)
  }

  public var failedDirectories: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return failed
  }
}
