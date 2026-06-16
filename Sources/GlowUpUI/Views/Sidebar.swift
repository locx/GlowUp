import SwiftUI

public enum NavSection: String, CaseIterable, Identifiable {
  case recommended = "Recommended"
  case advanced    = "Advanced"
  case reports     = "Reports"
  case history     = "History"
  case about       = "About"
  public var id: String { rawValue }

  var icon: String {
    switch self {
    case .recommended: return "sparkles"
    case .advanced:    return "gearshape.2"
    case .reports:     return "doc.text.magnifyingglass"
    case .history:     return "clock.arrow.circlepath"
    case .about:       return "info.circle"
    }
  }
}

struct Sidebar: View {
  @Binding var selection: NavSection

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        BrandMark(size: 26)
        Text("GlowUp").font(.title2.weight(.bold)).foregroundStyle(Color.textPrimary)
        Spacer()
      }
      .frame(maxHeight: GlowMetrics.headerBand)
      .padding(.horizontal, 14)
      Divider()
      // Custom rows so selection reads brand-green, not the macOS system accent.
      VStack(spacing: 2) {
        ForEach(NavSection.allCases) { s in
          SidebarRow(section: s, isSelected: selection == s) { selection = s }
        }
      }
      .padding(8)
      Spacer()
    }
  }
}

private struct SidebarRow: View {
  let section: NavSection
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      Label { Text(section.rawValue) } icon: { Image(systemName: section.icon) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? Color.brand.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isSelected ? Color.brand : Color.textPrimary)
    }
    .buttonStyle(.plain)
  }
}
