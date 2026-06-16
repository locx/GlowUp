import Foundation

// Runs an executable with args; injectable so the prune command is testable without launching it.
public protocol ShellRunner: Sendable {
  func run(_ launchPath: String, _ args: [String]) -> Bool
  // Captured stdout, or nil if the process couldn't launch.
  func output(_ launchPath: String, _ args: [String]) -> String?
}

public extension ShellRunner {
  // Default keeps existing fakes source-compatible; real detection needs ProcessRunner.
  func output(_ launchPath: String, _ args: [String]) -> String? { nil }
}

public struct ProcessRunner: ShellRunner {
  public init() {}
  public func run(_ launchPath: String, _ args: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
  }

  public func output(_ launchPath: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    do { try p.run() } catch { return nil }
    // Drain before waiting so a full pipe buffer can't deadlock the child.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }
}

// Removes simulator runtimes/devices macOS marks unavailable (old/uninstalled Xcode), via Apple's
// own simctl — the safe path; raw-deleting CoreSimulator/Devices would corrupt the simulator set.
public enum SimulatorCleaner {
  @discardableResult
  public static func deleteUnavailable(runner: ShellRunner = ProcessRunner()) -> Bool {
    runner.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
  }

  // Whether `delete unavailable` would have anything to remove — gates the UI row.
  public static func hasUnavailable(runner: ShellRunner = ProcessRunner()) -> Bool {
    guard let out = runner.output("/usr/bin/xcrun", ["simctl", "list", "devices"]) else { return false }
    return out.lowercased().contains("unavailable")
  }
}
