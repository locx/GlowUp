import SwiftUI
import GlowKit

// One source of truth for brand colors and tokens so views never hardcode them.
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

// Per-tier color paired with a label elsewhere, never color alone, for color-blind legibility.
public func color(for risk: Risk) -> Color {
  switch risk {
  case .safe:        return Color(hex: "#10B981") // emerald
  case .rebuildable: return Color(hex: "#0EA5E9") // sky
  case .stateful:    return Color(hex: "#FBBF24") // amber
  case .privacy:     return Color(hex: "#D946EF") // fuchsia
  }
}

// Central per-category icon + tint so every view renders a category identically.
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

// One motion policy so every view honors Reduce Motion the same way.
public enum Motion {
  /// Returns a spring animation when reduce-motion is off, a short opacity fade when on.
  public static func anim(_ reduce: Bool) -> Animation? {
    reduce
      ? .easeInOut(duration: 0.15)
      : .spring(response: 0.6, dampingFraction: 0.8)
  }
}

// Shared type styles so text scales and reads consistently across views.
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

  public func makeBody(configuration: Configuration) -> some View {
    StyledLabel(kind: kind, configuration: configuration)
  }

  // Hover and enabled must live in a real View, not the style struct, so SwiftUI keeps them in sync.
  private struct StyledLabel: View {
    let kind: Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
      configuration.label
        .font(Font.body.weight(.semibold))
        // Shared min width so full-size pills read as one even system across every page.
        .frame(minWidth: 110)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .foregroundStyle(textColor)
        .background(fill(pressed: configuration.isPressed), in: Capsule())
        .overlay { outline }
        .brightness(enabled && hovering && !configuration.isPressed ? 0.07 : 0)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var textColor: Color {
      switch kind {
      case .primary, .danger: return .white
      case .secondary:        return .textPrimary
      }
    }

    // Secondary is the only outlined kind; primary and danger are filled CTAs.
    @ViewBuilder private var outline: some View {
      switch kind {
      case .primary, .danger: EmptyView()
      // Full-strength ring; the button's overall opacity handles the disabled dim so it isn't faded twice.
      case .secondary:        Capsule().strokeBorder(Color.brand.opacity(0.9), lineWidth: 1.5)
      }
    }

    private func fill(pressed: Bool) -> Color {
      switch kind {
      case .primary:   return Color.brand.opacity(pressed ? 0.82 : 1)
      case .danger:    return Color.danger.opacity(pressed ? 0.82 : 1)
      case .secondary: return Color.surfaceRaised.opacity(pressed ? 0.7 : 1)
      }
    }
  }
}

public extension ButtonStyle where Self == GlowButtonStyle {
  static var glowPrimary: GlowButtonStyle { .init(kind: .primary) }
  static var glowSecondary: GlowButtonStyle { .init(kind: .secondary) }
  static var glowDanger: GlowButtonStyle { .init(kind: .danger) }
}

// Brand checkbox — keeps a green border when unchecked so it reads with the outlined buttons.
public struct GlowCheckboxStyle: ToggleStyle {
  var tint: Color = .brand
  // Bare drops the label so a label-less selection row reserves no trailing gap.
  var labeled: Bool = true

  public func makeBody(configuration: Configuration) -> some View {
    Checkbox(configuration: configuration, tint: tint, labeled: labeled)
  }

  // Hover lives in a real View so the toggle gets the same pointer feedback as the pills.
  private struct Checkbox: View {
    let configuration: ToggleStyleConfiguration
    let tint: Color
    let labeled: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
      Button { configuration.isOn.toggle() } label: {
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 4)
            .fill(configuration.isOn ? tint : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint, lineWidth: 1.5))
            .overlay {
              if configuration.isOn {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                  .foregroundStyle(.white)
              }
            }
            .frame(width: 16, height: 16)
          if labeled { configuration.label }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .brightness(enabled && hovering ? 0.08 : 0)
      .opacity(enabled ? 1 : 0.45)
      .onHover { hovering = $0 }
      .animation(.easeOut(duration: 0.12), value: hovering)
    }
  }
}

public extension ToggleStyle where Self == GlowCheckboxStyle {
  static var glowCheckbox: GlowCheckboxStyle { .init() }
  static var glowCheckboxBare: GlowCheckboxStyle { .init(labeled: false) }
  static var glowCheckboxBareDanger: GlowCheckboxStyle { .init(tint: .danger, labeled: false) }
}

// Inline status line — one icon+text idiom so warnings/errors read the same on every page.
// Content-sized + centered by default (hero/sheet); `leading` fills width for boxed list rows.
public struct StatusMessage: View {
  public enum Kind { case warning, danger }
  let text: String
  var kind: Kind = .warning
  var leading: Bool = false

  public init(_ text: String, kind: Kind = .warning, leading: Bool = false) {
    self.text = text
    self.kind = kind
    self.leading = leading
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: symbol).font(.callout)
      Text(text).font(.callout).multilineTextAlignment(leading ? .leading : .center)
      if leading { Spacer(minLength: 0) }
    }
    .foregroundStyle(kind == .danger ? Color.danger : Color.warning)
  }

  // Octagon reserves the most severe glyph for permanent/danger, matching the permanent group header.
  private var symbol: String {
    kind == .danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle"
  }
}

// Centered empty-state placeholder — one idiom so every "nothing here" page matches.
public struct EmptyState: View {
  let symbol: String
  let text: String

  public init(symbol: String, text: String) {
    self.symbol = symbol
    self.text = text
  }

  public var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 32))
        .foregroundStyle(Color.textSecondary)
      Text(text)
        .font(.body)
        .foregroundStyle(Color.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }
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
