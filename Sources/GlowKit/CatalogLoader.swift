import Foundation

public enum CatalogError: Error, Equatable {
  case unsupportedSchema(Int)
  case duplicateRuleID(String)
  case invalidGlob(String)
  case invalidProjectRoot(String)
  case invalidProjectArtifact(String)
  case missingResource
}

public enum CatalogLoader {
  // Exposes the module-bundle URL so callers can open the file without bundling it themselves.
  public static var bundledURL: URL? {
    // Probe the assembled .app's Resources first: SwiftPM's Bundle.module accessor only checks
    // the .app root and the build machine's absolute .build path, and fatalErrors when both miss.
    if let staged = Bundle.main.resourceURL?.appending(path: "GlowUp_GlowKit.bundle"),
       let bundle = Bundle(url: staged),
       let url = bundle.url(forResource: "catalog", withExtension: "json") {
      return url
    }
    return Bundle.module.url(forResource: "catalog", withExtension: "json")
  }

  public static func loadBundled() throws -> Catalog {
    guard let url = bundledURL else { throw CatalogError.missingResource }
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
        // Reject if first path segment contains '*' — would enumerate an entire base root.
        let firstSegmentHasWildcard = g.split(separator: "/", omittingEmptySubsequences: false)
          .first.map { $0.contains("*") } ?? false
        guard !g.isEmpty, !g.hasPrefix("/"),
              !g.contains("**"),
              !g.split(separator: "/").contains(".."),
              !firstSegmentHasWildcard
        else { throw CatalogError.invalidGlob(g) }
      }
    }
    // The advanced project walk is the broadest traversal, so its roots get parse-time validation:
    // roots must be home-relative ("~/…") with no ".." so the walk can't start outside $HOME.
    for root in cat.projectRoots {
      guard root.hasPrefix("~/"), !root.split(separator: "/").contains("..")
      else { throw CatalogError.invalidProjectRoot(root) }
    }
    // Artifacts match a single path component, so reject multi-segment or traversing entries.
    for artifact in cat.projectArtifacts
    where artifact.isEmpty || artifact.contains("/") || artifact == ".." {
      throw CatalogError.invalidProjectArtifact(artifact)
    }
    return cat
  }
}
