public enum Risk: String, Codable, CaseIterable, Sendable {
  case safe, stateful, privacy, rebuildable

  // Only safe-tier items are pre-selected; the rest are opt-in.
  public var isDefaultSelected: Bool { self == .safe }
}
