import Foundation

// Runs an executable with args; injectable so the prune command is testable without launching it.
public protocol ShellRunner: Sendable {
  func run(_ launchPath: String, _ args: [String]) -> Bool
}

public struct ProcessRunner: ShellRunner {
  public init() {}
  public func run(_ launchPath: String, _ args: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
  }
}

// Removes simulator runtimes/devices macOS marks unavailable (old/uninstalled Xcode), via Apple's
// own simctl — the safe path; raw-deleting CoreSimulator/Devices would corrupt the simulator set.
public enum SimulatorCleaner {
  @discardableResult
  public static func deleteUnavailable(runner: ShellRunner = ProcessRunner()) -> Bool {
    runner.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
  }
}
