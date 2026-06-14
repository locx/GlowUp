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

  // Keyed on the symlink-resolved path so scanners that name the same file collapse; sorting
  // contiguously after each ancestor keeps the descendant drop O(n log n), not O(n^2).
  public static func dedupe(_ candidates: [Candidate]) -> [Candidate] {
    // At an equal path keep the most-protected tier, then input order, so the result is
    // deterministic and a cleanable hit can never displace a privacy/stateful one.
    let keyed = candidates.enumerated()
      .map { (idx, c) in (PathUtil.canonicalPath(c.url), idx, c) }
      .sorted {
        if $0.0 != $1.0 { return $0.0 < $1.0 }
        if $0.2.risk.protectionRank != $1.2.risk.protectionRank {
          return $0.2.risk.protectionRank > $1.2.risk.protectionRank
        }
        return $0.1 < $1.1
      }
    var result: [Candidate] = []
    var lastIncluded: String?
    for (p, _, c) in keyed {
      if let last = lastIncluded, p == last || p.hasPrefix(last + "/") { continue }
      result.append(c)
      lastIncluded = p
    }
    return result
  }
}

extension Array where Element == Candidate {
  // Shared scanner contract: deterministic, path-ordered output.
  public func sortedByPath() -> [Candidate] { sorted { $0.url.path < $1.url.path } }
}
