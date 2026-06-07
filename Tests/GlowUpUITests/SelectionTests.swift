import XCTest
import GlowKit
@testable import GlowUpUI

final class SelectionTests: XCTestCase {
  private func cand(_ id: String, _ risk: Risk) -> Candidate {
    Candidate(ruleID: id, app: nil, category: "appCaches", risk: risk, why: "w",
              url: URL(fileURLWithPath: "/tmp/\(id)"))
  }

  func test_defaultSelectsSafeLeavesOnly() {
    let cands = [cand("a", .safe), cand("b", .stateful),
                 cand("c", .privacy), cand("d", .safe)]
    let sel = Selection.defaultSelected(cands)
    XCTAssertEqual(sel, Set([cands[0].id, cands[3].id]))
  }

  func test_emptyWhenNoSafe() {
    XCTAssertTrue(Selection.defaultSelected([cand("a", .stateful)]).isEmpty)
  }
}
