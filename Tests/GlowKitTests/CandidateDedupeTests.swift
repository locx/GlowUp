import XCTest
@testable import GlowKit

final class CandidateDedupeTests: XCTestCase {
  private func make(_ path: String) -> Candidate {
    Candidate(ruleID: "r", app: nil, category: "c", risk: .safe, why: "w",
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
