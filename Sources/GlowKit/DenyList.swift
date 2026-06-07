import Foundation

public enum DenyList {
  // Home-relative directories whose contents are never cleanup candidates.
  private static let protectedRelDirs = [
    "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
    "Library/Mail", "Library/Messages", "Library/Keychains",
    "Library/Mobile Documents",
    "Library/Application Support/MobileSync",
    ".ssh", ".gnupg", ".aws", ".config/gh", ".kube",
  ]

  // Filenames that signal credentials regardless of location.
  private static let credentialSuffixes = [
    ".kdbx", ".pem", ".key", ".p12", ".netrc", ".pgpass",
  ]
  private static let credentialPrefixes = ["id_rsa", ".env"]

  public static func vetoes(_ url: URL, home: URL) -> Bool {
    // Reject before canonicalization if the literal path tries to traverse up.
    if url.pathComponents.contains("..") { return true }

    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    // Resolve home so symlinked $HOME and resolved candidate paths are compared in the same space.
    let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
    let resolvedHome = URL(fileURLWithPath: homePath)

    // Never act on a bare base root.
    for base in BaseRoot.allCases where path == base.url(home: resolvedHome).path {
      return true
    }

    for rel in protectedRelDirs {
      let prot = resolvedHome.appending(path: rel).path
      if path == prot || path.hasPrefix(prot + "/") { return true }
    }

    // Use the resolved target's filename so symlinks named `cache` -> credential are caught.
    let name = URL(fileURLWithPath: path).lastPathComponent
    if credentialSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
    if credentialPrefixes.contains(where: { name.hasPrefix($0) }) { return true }

    // Anything outside the home dir is out of scope for the user-safe path.
    if path != homePath, !path.hasPrefix(homePath + "/") { return true }

    return false
  }
}
