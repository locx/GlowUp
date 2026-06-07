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
