import SwiftUI
import GlowKit

// Emerald Graphite brand palette and design tokens (spec §7).
public extension Color {
  /// Creates a Color from a hex string like "#10B981" or "10B981".
  init(hex: String) {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let v = UInt64(h, radix: 16) ?? 0
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    self.init(red: r, green: g, blue: b)
  }

  // Brand accent: emerald green on graphite dark background.
  static let brand      = Color(hex: "#10B981")
  static let graphite   = Color(hex: "#16181A")
  // Amber: used for warnings and non-safe risk highlights.
  static let warning    = Color(hex: "#FBBF24")
  // Red: reserved for permanent, non-recoverable actions only.
  static let danger     = Color(hex: "#FF453A")

  // Surface tokens — dark-leaning; adapt to system appearance.
  static let surface       = Color(NSColor.windowBackgroundColor)
  static let surfaceRaised = Color(NSColor.controlBackgroundColor)
  static let textPrimary   = Color(NSColor.labelColor)
  static let textSecondary = Color(NSColor.secondaryLabelColor)
}

// Maps internal category keys to user-visible names for display in grouped lists.
public func categoryName(_ category: String) -> String {
  switch category {
  case "browserData":         return "Browser data"
  case "appCaches":           return "App caches"
  case "systemLogs":          return "System logs"
  case "libraryOrphans":      return "Library orphans"
  case "projectArtifacts":    return "Project artifacts"
  case "duplicateExtensions": return "Duplicate extensions"
  case "workspaceOrphans":    return "Workspace orphans"
  default:                    return category
  }
}

// Risk tier palette (color + label, never color alone — spec §5).
public func color(for risk: Risk) -> Color {
  switch risk {
  case .safe:        return Color(hex: "#10B981") // emerald
  case .rebuildable: return Color(hex: "#0EA5E9") // sky
  case .stateful:    return Color(hex: "#FBBF24") // amber
  case .privacy:     return Color(hex: "#D946EF") // fuchsia
  }
}

// Category → SF Symbol name + tint color (spec §7).
public struct CategoryGlyph {
  public let symbol: String
  public let tint: Color
}

// Shared so the ring and the legend never disagree; "other" is the folded sub-threshold bucket.
public func categoryTint(_ category: String) -> Color {
  category == "other" ? .secondary : glyph(for: category).tint
}

public func glyph(for category: String) -> CategoryGlyph {
  switch category {
  case "browserData":          return CategoryGlyph(symbol: "globe",                  tint: Color(hex: "#0EA5E9"))
  case "appCaches":            return CategoryGlyph(symbol: "shippingbox",            tint: Color(hex: "#10B981"))
  case "systemLogs":           return CategoryGlyph(symbol: "doc.text",               tint: Color(hex: "#FBBF24"))
  case "libraryOrphans":       return CategoryGlyph(symbol: "questionmark.folder",    tint: Color(hex: "#D946EF"))
  case "projectArtifacts":     return CategoryGlyph(symbol: "hammer",                 tint: Color(hex: "#F97316"))
  case "duplicateExtensions":  return CategoryGlyph(symbol: "square.on.square",       tint: Color(hex: "#8B5CF6"))
  case "workspaceOrphans":     return CategoryGlyph(symbol: "archivebox",             tint: Color(hex: "#6B7280"))
  default:                     return CategoryGlyph(symbol: "folder",                 tint: .secondary)
  }
}

// Centralized motion policy (spec §8).
public enum Motion {
  /// Returns a spring animation when reduce-motion is off, a short opacity fade when on.
  public static func anim(_ reduce: Bool) -> Animation? {
    reduce
      ? .easeInOut(duration: 0.15)
      : .spring(response: 0.6, dampingFraction: 0.8)
  }
}

// Typography helpers (spec §7).
public extension Font {
  /// Large metric display — 40pt semibold rounded with monospaced digits.
  static var heroNumber: Font {
    .system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
  }
}

// Shared 8pt-rhythm outer padding for non-list detail panels.
public extension View {
  func pagePadding() -> some View { self.padding(20) }
}

public enum GlowMetrics {
  // Top-band height shared by the sidebar brand row and every page header so their dividers align.
  public static let headerBand: CGFloat = 56
}

// Shared button styles so every action reads the same across pages.
public struct GlowButtonStyle: ButtonStyle {
  public enum Kind { case primary, secondary, danger }
  let kind: Kind
  var compact: Bool = false
  @Environment(\.isEnabled) private var enabled

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font((compact ? Font.caption : .body).weight(.semibold))
      .padding(.horizontal, compact ? 12 : 18)
      .padding(.vertical, compact ? 5 : 9)
      .foregroundStyle(textColor)
      .background(fill(pressed: configuration.isPressed), in: Capsule())
      .overlay { outline }
      .opacity(enabled ? 1 : 0.45)
      .contentShape(Capsule())
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  private var textColor: Color {
    switch kind {
    case .primary:   return .white
    case .secondary: return .textPrimary
    case .danger:    return .danger
    }
  }

  // Outline distinguishes the non-filled styles: brand for secondary, red for permanent/danger.
  @ViewBuilder private var outline: some View {
    switch kind {
    case .primary:   EmptyView()
    case .secondary: Capsule().strokeBorder(Color.brand.opacity(enabled ? 0.9 : 0.4), lineWidth: 1.5)
    case .danger:    Capsule().strokeBorder(Color.danger.opacity(enabled ? 0.9 : 0.4), lineWidth: 1.5)
    }
  }

  private func fill(pressed: Bool) -> Color {
    switch kind {
    case .primary:            return Color.brand.opacity(pressed ? 0.82 : 1)
    case .secondary, .danger: return Color.surfaceRaised.opacity(pressed ? 0.7 : 1)
    }
  }
}

public extension ButtonStyle where Self == GlowButtonStyle {
  static var glowPrimary: GlowButtonStyle { .init(kind: .primary) }
  static var glowSecondary: GlowButtonStyle { .init(kind: .secondary) }
  static var glowSecondaryCompact: GlowButtonStyle { .init(kind: .secondary, compact: true) }
  static var glowDanger: GlowButtonStyle { .init(kind: .danger) }
}

// Consistent leading-aligned page header so every detail page reads the same.
public struct PageHeader: View {
  let title: String
  var subtitle: String?

  public init(_ title: String, subtitle: String? = nil) {
    self.title = title
    self.subtitle = subtitle
  }

  public var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
        if let subtitle {
          Text(subtitle).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: GlowMetrics.headerBand, alignment: .leading)
      .padding(.horizontal, 20)
      Divider()
    }
  }
}
