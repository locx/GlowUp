import Foundation

public struct Candidate: Sendable, Identifiable, Equatable {
  public let ruleID: String
  public let app: String?
  public let category: String
  public let risk: Risk
  public let why: String
  public let url: URL

  // Stable across runs so selection/restore can key on it.
  public var id: String { "\(ruleID)\u{0}\(url.path)" }

  public init(ruleID: String, app: String?, category: String,
              risk: Risk, why: String, url: URL) {
    self.ruleID = ruleID; self.app = app; self.category = category
    self.risk = risk; self.why = why; self.url = url
  }
}
