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
  // ".key" is excluded here because Keynote/license/cache files make it too ambiguous to veto a parent dir.
  private static let credentialChildSuffixes = [".kdbx", ".pem", ".p12", ".netrc", ".pgpass"]

  // Resolve home so symlinked $HOME and resolved candidate paths are compared in the same space.
  public static func vetoes(_ url: URL, home: URL) -> Bool {
    vetoes(url, resolvedHomePath: home.standardizedFileURL.resolvingSymlinksInPath().path)
  }

  // Takes the already-resolved home path so a scan resolves $HOME once, not once per candidate.
  static func vetoes(_ url: URL, resolvedHomePath: String) -> Bool {
    // Reject before canonicalization if the literal path tries to traverse up.
    if url.pathComponents.contains("..") { return true }

    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let homePath = resolvedHomePath
    let resolvedHome = URL(fileURLWithPath: homePath)

    // Never act on a bare base root (case-insensitive for macOS volumes).
    for base in BaseRoot.allCases where path.lowercased() == base.url(home: resolvedHome).path.lowercased() {
      return true
    }

    for rel in protectedRelDirs {
      let prot = resolvedHome.appending(path: rel).path
      // Case-insensitive so e.g. "documents" matches the protected "Documents".
      if path.lowercased() == prot.lowercased()
        || path.lowercased().hasPrefix(prot.lowercased() + "/") { return true }
    }

    // Anything outside the home dir is out of scope — skip the expensive listdir (case-insensitive).
    if path.lowercased() != homePath.lowercased(),
       !path.lowercased().hasPrefix(homePath.lowercased() + "/") { return true }

    // Use the resolved target's filename so symlinks named `cache` -> credential are caught.
    let name = URL(fileURLWithPath: path).lastPathComponent
    if credentialSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
    if credentialPrefixes.contains(where: { name.hasPrefix($0) }) { return true }

    // Veto directories whose shallow tree contains credential-named files.
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
       hasCredentialChild(URL(fileURLWithPath: path), depth: 0) { return true }

    return false
  }

  // Bounded depth matching the data-store guard, probed fresh on every veto so a newly added
  // credential isn't missed. Symlinked children are skipped: trashing the parent leaves its target.
  private static func hasCredentialChild(_ dir: URL, depth: Int) -> Bool {
    guard depth <= 3 else { return false }
    let fm = FileManager.default
    guard let children = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
    for child in children {
      if credentialChildSuffixes.contains(where: { child.hasSuffix($0) })
        || credentialPrefixes.contains(where: { child.hasPrefix($0) }) { return true }
      let url = dir.appending(path: child)
      if let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
         vals.isSymbolicLink != true, vals.isDirectory == true,
         hasCredentialChild(url, depth: depth + 1) { return true }
    }
    return false
  }
}
