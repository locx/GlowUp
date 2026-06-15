import XCTest
@testable import GlowKit

final class CandidateDedupeTests: XCTestCase {
  private func make(_ path: String, _ risk: Risk = .safe) -> Candidate {
    Candidate(ruleID: "r", app: nil, category: "c", risk: risk, why: "w",
              url: URL(fileURLWithPath: path))
  }

  func test_dedupeRemovesDuplicatePaths() {
    let a = make("/a/b")
    let b = make("/a/b")   // same path, different instance
    let result = Candidate.dedupe([a, b])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].url.path, "/a/b")
  }

  func test_dedupeDropsDescendantOfEarlierCandidate() {
    let parent = make("/a")
    let child  = make("/a/b")
    let result = Candidate.dedupe([parent, child])
    // Parent retained; child dropped as a descendant.
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].url.path, "/a")
  }

  func test_dedupeKeepsUnrelatedPaths() {
    let x = make("/a/b")
    let y = make("/a/c")
    let result = Candidate.dedupe([x, y])
    XCTAssertEqual(result.count, 2)
  }

  func test_dedupeKeepsMostProtectedOnDuplicatePath() {
    let safe = Candidate(ruleID: "swept", app: nil, category: "c", risk: .safe,
                         why: "w", url: URL(fileURLWithPath: "/x"))
    let privacy = Candidate(ruleID: "catalog", app: nil, category: "c", risk: .privacy,
                            why: "w", url: URL(fileURLWithPath: "/x"))
    // Order-independent: the privacy hit must win so a cleanable one can't displace it.
    XCTAssertEqual(Candidate.dedupe([safe, privacy]).first?.risk, .privacy)
    XCTAssertEqual(Candidate.dedupe([privacy, safe]).first?.risk, .privacy)
  }

  func test_dedupeExcludesSubtreeWhenDescendantMoreProtected() {
    // A safe parent must not trash a privacy child nested under it: drop the whole subtree.
    let result = Candidate.dedupe([make("/a", .safe), make("/a/b", .privacy)])
    XCTAssertTrue(result.isEmpty)
  }

  func test_dedupeExcludesSubtreeWithSiblingsWhenDescendantMoreProtected() {
    let result = Candidate.dedupe([make("/a", .safe), make("/a/b", .privacy), make("/a/c", .safe)])
    XCTAssertTrue(result.isEmpty, "no part of a subtree holding protected data is trashed")
  }

  func test_dedupeKeepsUnrelatedPathAfterExcludedSubtree() {
    let result = Candidate.dedupe([make("/a", .safe), make("/a/b", .privacy), make("/z", .safe)])
    XCTAssertEqual(result.map(\.url.path), ["/z"])
  }

  func test_dedupeExcludesTwoIndependentSubtrees() {
    // Each subtree holding a more-protected path is dropped whole, independently.
    let result = Candidate.dedupe([make("/a", .safe), make("/a/b", .privacy),
                                   make("/b", .safe), make("/b/y", .privacy)])
    XCTAssertTrue(result.isEmpty)
  }

  func test_dedupeKeepsLessProtectedDescendantUnderMoreProtectedAncestor() {
    // Reverse case unchanged: privacy parent retained, safe child collapsed (parent not auto-cleaned).
    let result = Candidate.dedupe([make("/a", .privacy), make("/a/b", .safe)])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].risk, .privacy)
  }

  func test_dedupeKeepsFirstOnDuplicate() {
    let first  = Candidate(ruleID: "r1", app: nil, category: "c", risk: .safe,
                           why: "first", url: URL(fileURLWithPath: "/x"))
    let second = Candidate(ruleID: "r2", app: nil, category: "c", risk: .safe,
                           why: "second", url: URL(fileURLWithPath: "/x"))
    let result = Candidate.dedupe([first, second])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].why, "first")
  }
}
