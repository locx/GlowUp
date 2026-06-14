import GlowKit

public enum Selection {
  // Pre-checked by default: the tiers advanced-clean will actually trash; privacy/stateful stay opt-in.
  public static func defaultSelected(_ candidates: [Candidate]) -> Set<String> {
    Set(candidates.filter { Risk.defaultSelectable.contains($0.risk) }.map(\.id))
  }
}
