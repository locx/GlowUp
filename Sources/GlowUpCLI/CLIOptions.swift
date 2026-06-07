public struct CLIOptions: Equatable {
  public enum Mode: Equatable { case list, dryRun, clean, restore, projects }

  public var mode: Mode = .dryRun
  public var advanced = false
  public var json = false
  public var noColor = false
  public var unknown: [String] = []

  // Last mode flag wins; non-mode flags accumulate. Unknown flags are recorded.
  public static func parse(_ args: [String]) -> CLIOptions {
    var o = CLIOptions()
    for arg in args {
      switch arg {
      case "--list":     o.mode = .list
      case "--dry-run":  o.mode = .dryRun
      case "--clean":    o.mode = .clean
      case "--restore":  o.mode = .restore
      case "--projects": o.mode = .projects
      case "--advanced": o.advanced = true
      case "--json":     o.json = true
      case "--no-color": o.noColor = true
      default:           o.unknown.append(arg)
      }
    }
    return o
  }
}
