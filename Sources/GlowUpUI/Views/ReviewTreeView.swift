import SwiftUI
import GlowKit

struct ReviewTreeView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    List {
      ForEach(model.candidates) { c in
        HStack {
          Toggle("", isOn: binding(for: c)).labelsHidden()
          VStack(alignment: .leading) {
            Text(c.app ?? c.ruleID)
            Text(c.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          RiskCapsule(risk: c.risk)
          Text(ReclaimLabel.format(model.sizes[c.id] ?? 0)).monospacedDigit()
        }
      }
    }
    .navigationTitle("Review what will be cleaned")
  }

  private func binding(for c: Candidate) -> Binding<Bool> {
    Binding(get: { model.selected.contains(c.id) },
            set: { on in if on { model.selected.insert(c.id) } else { model.selected.remove(c.id) } })
  }
}

struct RiskCapsule: View {
  let risk: Risk
  var body: some View {
    Text(label).font(.caption2.smallCaps())
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(color.opacity(0.2), in: Capsule())
      .foregroundStyle(color)
  }
  private var label: String { String(describing: risk) }
  private var color: Color {
    switch risk {
    case .safe: return .green
    case .rebuildable: return .blue
    case .stateful: return .yellow
    case .privacy: return .purple
    }
  }
}
