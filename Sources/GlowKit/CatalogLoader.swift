import Foundation

public enum CatalogError: Error, Equatable {
  case unsupportedSchema(Int)
  case duplicateRuleID(String)
  case invalidGlob(String)
  case missingResource
}

public enum CatalogLoader {
  public static func loadBundled() throws -> Catalog {
    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json")
    else { throw CatalogError.missingResource }
    return try load(data: Data(contentsOf: url))
  }

  public static func load(data: Data) throws -> Catalog {
    let cat = try JSONDecoder().decode(Catalog.self, from: data)
    guard cat.schemaVersion == 1 else {
      throw CatalogError.unsupportedSchema(cat.schemaVersion)
    }
    var seen = Set<String>()
    for rule in cat.rules {
      guard seen.insert(rule.id).inserted else {
        throw CatalogError.duplicateRuleID(rule.id)
      }
      for spec in rule.paths {
        let g = spec.glob
        guard !g.isEmpty, !g.hasPrefix("/"),
              !g.contains("**"),
              !g.split(separator: "/").contains("..")
        else { throw CatalogError.invalidGlob(g) }
      }
    }
    return cat
  }
}
