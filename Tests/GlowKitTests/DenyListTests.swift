import XCTest
@testable import GlowKit

final class DenyListTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/Users/test")

  // Every hostile path must be vetoed.
  func test_vetoesProtectedLocations() {
    let hostile = [
      "/Users/test/Documents/report.txt",
      "/Users/test/Desktop/a",
      "/Users/test/Downloads/x",
      "/Users/test/Pictures/Photos Library.photoslibrary",
      "/Users/test/Movies/film.mov",
      "/Users/test/Library/Mail/box",
      "/Users/test/Library/Keychains/login.keychain-db",
      "/Users/test/Library/Mobile Documents/iCloud~x",
      "/Users/test/Library/Application Support/MobileSync/Backup/dev",
      "/Users/test/.ssh/id_rsa",
      "/Users/test/.gnupg/secring",
      "/Users/test/Library/Caches/secret.kdbx",
      "/Users/test/Library/Caches/app/private.key",
    ]
    for p in hostile {
      XCTAssertTrue(DenyList.vetoes(URL(fileURLWithPath: p), home: home),
                    "should veto \(p)")
    }
  }

  // A base root itself must be vetoed (never nuke all of ~/Library/Caches).
  func test_vetoesBaseRootItself() {
    XCTAssertTrue(DenyList.vetoes(BaseRoot.caches.url(home: home), home: home))
    XCTAssertTrue(DenyList.vetoes(BaseRoot.appSupport.url(home: home), home: home))
  }

  // A genuine cache path must NOT be vetoed.
  func test_allowsGenuineCachePath() {
    let ok = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app")
    XCTAssertFalse(DenyList.vetoes(ok, home: home))
  }

  // Credentials nested below the first level must still veto their parent dir.
  func test_vetoesDirectoryWithNestedCredentialFile() throws {
    let realHome = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-deny-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: realHome) }
    let candidate = realHome.appending(path: "Library/Caches/FooApp")
    try FileManager.default.createDirectory(
      at: candidate.appending(path: "config"), withIntermediateDirectories: true)
    try Data().write(to: candidate.appending(path: "config/id_rsa"))

    XCTAssertTrue(DenyList.vetoes(candidate, home: realHome))
  }

  // A credential nested two levels below the candidate dir must still veto it.
  func test_vetoesDirectoryWithDeeplyNestedCredentialFile() throws {
    let realHome = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "glow-deny-deep-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: realHome) }
    let candidate = realHome.appending(path: "Library/Caches/FooApp")
    try FileManager.default.createDirectory(
      at: candidate.appending(path: "config/sub"), withIntermediateDirectories: true)
    try Data().write(to: candidate.appending(path: "config/sub/id_rsa"))

    XCTAssertTrue(DenyList.vetoes(candidate, home: realHome))
  }

  func test_vetoesParentTraversal() {
    let p = URL(fileURLWithPath: "/Users/test/Library/Caches/../../Documents")
    XCTAssertTrue(DenyList.vetoes(p, home: home))
  }

  // A symlink inside Caches pointing at ~/Documents must be vetoed (symlink-escape).
  func test_vetoesSymlinkEscapingCaches() throws {
    let fm = FileManager.default
    let tmpBase = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let realHome = tmpBase.appendingPathComponent("realhome")
    defer { try? fm.removeItem(at: tmpBase) }

    try fm.createDirectory(at: realHome.appendingPathComponent("Documents"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: realHome.appendingPathComponent("Library/Caches"),
                           withIntermediateDirectories: true)

    let symlink = realHome.appendingPathComponent("Library/Caches/escape")
    try fm.createSymbolicLink(at: symlink,
                              withDestinationURL: realHome.appendingPathComponent("Documents"))

    // Resolve both sides through the same pipeline to mirror the fixed impl.
    let resolvedHome = realHome.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedSymlink = symlink.standardizedFileURL.resolvingSymlinksInPath()
    XCTAssertTrue(DenyList.vetoes(resolvedSymlink, home: resolvedHome),
                  "symlink escaping Caches into Documents must be vetoed")
  }

  // Case-insensitive protected-dir check: lowercase "documents" must still be vetoed.
  func test_vetoesProtectedDirCaseInsensitive() {
    let p = URL(fileURLWithPath: "/Users/test/documents/secret")
    XCTAssertTrue(DenyList.vetoes(p, home: home),
                  "lowercase 'documents' must be vetoed as protected dir")
  }

  // A directory whose immediate child is a credential file must be vetoed.
  func test_vetoesDirectoryContainingCredentialFile() throws {
    let fm = FileManager.default
    // Use a temp dir as the fake home so candidate paths are within home scope.
    let fakeHome = fm.temporaryDirectory
      .appendingPathComponent("glow-denylist-cred-\(UUID().uuidString)")
    let caches = fakeHome.appendingPathComponent("Library/Caches")
    let credDir = caches.appendingPathComponent("mysecrets")
    let blobDir = caches.appendingPathComponent("safe")
    defer { try? fm.removeItem(at: fakeHome) }

    try fm.createDirectory(at: credDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: blobDir, withIntermediateDirectories: true)
    // Credential file inside credDir.
    try Data().write(to: credDir.appendingPathComponent("id_rsa"))
    // Non-credential file inside blobDir.
    try Data().write(to: blobDir.appendingPathComponent("blob.bin"))

    XCTAssertTrue(DenyList.vetoes(credDir, home: fakeHome),
                  "directory containing id_rsa must be vetoed")
    XCTAssertFalse(DenyList.vetoes(blobDir, home: fakeHome),
                   "directory containing only blob.bin must not be vetoed")
  }

  // A genuine cache path under a SYMLINKED home must NOT be vetoed (regression for Fix 1).
  func test_allowsGenuineCacheUnderSymlinkedHome() throws {
    let fm = FileManager.default
    let tmpBase = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let realHome = tmpBase.appendingPathComponent("realhome")
    let linkHome = tmpBase.appendingPathComponent("linkhome")
    defer { try? fm.removeItem(at: tmpBase) }

    let cacheDir = realHome.appendingPathComponent("Library/Caches/com.example.app")
    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: linkHome, withDestinationURL: realHome)

    let candidateViaLink = linkHome.appendingPathComponent("Library/Caches/com.example.app")
    XCTAssertFalse(DenyList.vetoes(candidateViaLink, home: linkHome),
                   "genuine cache under symlinked home must not be vetoed")
  }
}
