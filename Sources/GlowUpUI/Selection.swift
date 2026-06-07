import GlowKit

public enum Selection {
  // ⌘A / default selection: safe-tier candidates only; never pulls non-safe.
  public static func defaultSelected(_ candidates: [Candidate]) -> Set<String> {
    Set(candidates.filter { $0.risk == .safe }.map(\.id))
  }
}
