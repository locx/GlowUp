import XCTest
@testable import GlowKit

final class CatalogModelTests: XCTestCase {
  func test_decodesRuleWithPerPathRiskOverride() throws {
    let json = """
    { "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [],
      "rules": [
        { "id": "x", "category": "appCaches", "risk": "safe", "why": "w",
          "paths": [
            { "base": "caches", "glob": "A" },
            { "base": "appSupport", "glob": "B/WebStorage", "risk": "stateful" }
          ] } ] }
    """
    let cat = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    XCTAssertEqual(cat.rules.count, 1)
    let r = cat.rules[0]
    XCTAssertNil(r.paths[0].risk)              // inherits rule risk
    XCTAssertEqual(r.paths[1].risk, .stateful) // overrides
  }

  func test_effectiveRiskFallsBackToRule() throws {
    let p = PathSpec(base: .caches, glob: "A", risk: nil)
    XCTAssertEqual(p.effectiveRisk(ruleRisk: .safe), .safe)
    let q = PathSpec(base: .caches, glob: "A", risk: .privacy)
    XCTAssertEqual(q.effectiveRisk(ruleRisk: .safe), .privacy)
  }
}
