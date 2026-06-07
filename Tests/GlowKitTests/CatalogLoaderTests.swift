import XCTest
@testable import GlowKit

final class CatalogLoaderTests: XCTestCase {
  private func decode(_ s: String) throws -> Catalog {
    try CatalogLoader.load(data: Data(s.utf8))
  }

  func test_loadsBundledCatalog() throws {
    let cat = try CatalogLoader.loadBundled()
    XCTAssertEqual(cat.schemaVersion, 1)
    XCTAssertFalse(cat.rules.isEmpty)
  }

  func test_rejectsWrongSchemaVersion() {
    let s = #"{ "schemaVersion": 2, "rules": [], "projectRoots": [], "projectArtifacts": [] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .unsupportedSchema(2))
    }
  }

  func test_rejectsDuplicateRuleIDs() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"X"}]}, {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"Y"}]} ] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .duplicateRuleID("a"))
    }
  }

  func test_rejectsGlobWithParentTraversal() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"../escape"}]} ] }"#
    XCTAssertThrowsError(try decode(s)) {
      XCTAssertEqual($0 as? CatalogError, .invalidGlob("../escape"))
    }
  }

  func test_rejectsAbsoluteOrEmptyGlob() {
    for bad in ["/abs", ""] {
      let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"\#(bad)"}]} ] }"#
      XCTAssertThrowsError(try decode(s), "glob \(bad) should be rejected")
    }
  }

  func test_rejectsDoubleStarGlob() {
    let s = #"{ "schemaVersion": 1, "projectRoots": [], "projectArtifacts": [], "rules": [ {"id":"a","category":"c","risk":"safe","why":"w","paths":[{"base":"caches","glob":"App/**/Cache"}]} ] }"#
    XCTAssertThrowsError(try CatalogLoader.load(data: Data(s.utf8))) {
      XCTAssertEqual($0 as? CatalogError, .invalidGlob("App/**/Cache"))
    }
  }
}
