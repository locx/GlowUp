import XCTest
@testable import GlowKit

final class CandidateTests: XCTestCase {
  func test_idIsStableForRuleAndPath() {
    let url = URL(fileURLWithPath: "/Users/test/Library/Caches/Code/CachedData")
    let a = Candidate(ruleID: "vscode.caches", app: "Visual Studio Code",
                      category: "appCaches", risk: .safe, why: "w", url: url)
    let b = Candidate(ruleID: "vscode.caches", app: "Visual Studio Code",
                      category: "appCaches", risk: .safe, why: "w", url: url)
    XCTAssertEqual(a.id, b.id)
    XCTAssertEqual(a, b)
  }

  func test_idDiffersByPath() {
    let u1 = URL(fileURLWithPath: "/Users/test/Library/Caches/A")
    let u2 = URL(fileURLWithPath: "/Users/test/Library/Caches/B")
    let a = Candidate(ruleID: "r", app: nil, category: "c", risk: .safe, why: "w", url: u1)
    let b = Candidate(ruleID: "r", app: nil, category: "c", risk: .safe, why: "w", url: u2)
    XCTAssertNotEqual(a.id, b.id)
  }
}
