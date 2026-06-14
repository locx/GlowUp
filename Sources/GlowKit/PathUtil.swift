import Foundation

public enum PathUtil {
  /// Expands a leading ~/ or bare ~ to the given home URL; absolute paths are returned unchanged.
  public static func expandingTilde(_ path: String, home: URL) -> URL {
    if path.hasPrefix("~/") {
      return home.appending(path: String(path.dropFirst(2)))
    } else if path == "~" {
      return home
    }
    return URL(fileURLWithPath: path)
  }

  // Follow symlinks without the lexical `..`-collapse that `standardizedFileURL` would apply,
  // so a planted `..` survives to the deny-list rather than being silently resolved away.
  public static func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
}
