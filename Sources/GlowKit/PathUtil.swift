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

  // Resolve-only canonicalization: follow symlinks without the lexical `..`-collapse that
  // `standardizedFileURL` would apply. DenyList resolves home+candidate symmetrically and stays inline.
  public static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath() }
  public static func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().path }
}
