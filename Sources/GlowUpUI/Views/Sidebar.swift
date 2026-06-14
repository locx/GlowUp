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
      List(NavSection.allCases, selection: $selection) { s in
        Label { Text(s.rawValue) } icon: { Image(systemName: s.icon) }
          .tag(s)
      }
      .listStyle(.sidebar)
    }
    .navigationTitle("GlowUp")
  }
}
