import Foundation

// Records wall-clock spans between phases so a perf measurement has real before/after numbers
// instead of guesses; uses the monotonic uptime clock so it isn't skewed by wall-clock changes.
public struct ScanTimer {
  private var last = DispatchTime.now()
  private var marks: [(label: String, ms: Int)] = []

  public init() {}

  public mutating func mark(_ label: String) {
    let now = DispatchTime.now()
    marks.append((label, Int(clamping: (now.uptimeNanoseconds &- last.uptimeNanoseconds) / 1_000_000)))
    last = now
  }

  public var report: [(label: String, ms: Int)] { marks }
}
