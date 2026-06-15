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
    dedupe(candidates, canonical: { PathUtil.canonicalPath($0.url) })
  }

  // Variant taking a canonical-path provider so a caller that already resolved each path (the
  // overlap filter) doesn't pay for a second symlink resolution here.
  static func dedupe(_ candidates: [Candidate], canonical: (Candidate) -> String) -> [Candidate] {
    // At an equal path keep the most-protected tier, then input order, so the result is
    // deterministic and a cleanable hit can never displace a privacy/stateful one.
    let keyed = candidates.enumerated()
      .map { (idx, c) in (canonical(c), idx, c) }
      .sorted {
        if $0.0 != $1.0 { return $0.0 < $1.0 }
        if $0.2.risk.protectionRank != $1.2.risk.protectionRank {
          return $0.2.risk.protectionRank > $1.2.risk.protectionRank
        }
        return $0.1 < $1.1
      }
    var result: [Candidate] = []
    var lastIncluded: (path: String, rank: Int)?
    // A subtree holding a more-protected path than its ancestor is dropped whole, so a cleanable
    // parent can never trash a privacy/stateful child nested beneath it.
    var excludedPrefix: String?
    for (p, _, c) in keyed {
      if let ex = excludedPrefix, p == ex || p.hasPrefix(ex + "/") { continue }
      excludedPrefix = nil
      if let last = lastIncluded, p == last.path || p.hasPrefix(last.path + "/") {
        if c.risk.protectionRank > last.rank {
          result.removeLast()
          excludedPrefix = last.path
          lastIncluded = nil
        }
        continue
      }
      result.append(c)
      lastIncluded = (p, c.risk.protectionRank)
    }
    return result
  }
}

extension Array where Element == Candidate {
  // Shared scanner contract: deterministic, path-ordered output.
  public func sortedByPath() -> [Candidate] { sorted { $0.url.path < $1.url.path } }
}
