import Foundation

public struct PathSpec: Codable, Sendable, Equatable {
  public let base: BaseRoot
  public let glob: String
  public let risk: Risk?

  public init(base: BaseRoot, glob: String, risk: Risk? = nil) {
    self.base = base; self.glob = glob; self.risk = risk
  }

  public func effectiveRisk(ruleRisk: Risk) -> Risk { risk ?? ruleRisk }
}

public struct Rule: Codable, Sendable, Identifiable {
  public let id: String
  public let app: String?
  public let appBundleID: String?
  public let requiresInstalled: Bool?
  public let category: String
  public let risk: Risk
  public let why: String
  public let paths: [PathSpec]
}

public struct Catalog: Codable, Sendable {
  public let schemaVersion: Int
  public let rules: [Rule]
  public let projectRoots: [String]
  public let projectArtifacts: [String]

  /// Fallback when the bundled catalog can't load: scans find nothing, cleans nothing.
  public static let empty = Catalog(schemaVersion: 1, rules: [],
                                    projectRoots: [], projectArtifacts: [])
}
