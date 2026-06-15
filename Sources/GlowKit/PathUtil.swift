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

  // Canonicalize by following symlinks (DenyList's own pre-resolution `..` check is what
  // catches traversal; this just gives every layer one consistent resolved path to compare).
  public static func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

  // A subtree we're denied from reading can't be proven free of credentials/stores,
  // so the safety probes veto on permission-denied rather than assume the dir is clean.
  static func isPermissionDenied(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(EACCES)
    }
    return false
  }
}
