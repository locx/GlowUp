public enum Risk: String, Codable, CaseIterable, Sendable {
  case safe, stateful, privacy, rebuildable

  // Pre-checked by default and trashable in basic mode; privacy/stateful stay opt-in.
  public static let defaultSelectable: Set<Risk> = [.safe, .rebuildable]

  // Tiers a scan surfaces: everything under Advanced, safe-only otherwise.
  public static func scanTiers(advanced: Bool) -> Set<Risk> {
    advanced ? Set(allCases) : [.safe]
  }

  // Tiers a clean may trash: privacy/stateful are never swept, even under Advanced.
  public static func cleanTiers(advanced: Bool) -> Set<Risk> {
    advanced ? defaultSelectable : [.safe]
  }

  // Human label for the tier badge (UI capsule + CLI tag).
  public var displayName: String { rawValue }

  // Higher = more protected from auto-clean; lets dedupe break path ties conservatively
  // so a cleanable candidate can never displace a privacy/stateful one at the same path.
  public var protectionRank: Int {
    switch self {
    case .privacy: 3
    case .stateful: 2
    case .rebuildable: 1
    case .safe: 0
    }
  }
}
