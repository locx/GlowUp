import SwiftUI
import GlowKit

public struct ContentView: View {
  @StateObject private var model: AppModel
  @State private var confirming = false
  @State private var section: Section = .recommended

  enum Section: String, CaseIterable, Identifiable {
    case recommended = "Recommended", advanced = "Advanced"
    case reports = "Reports", history = "History"
    var id: String { rawValue }
  }

  public init(model: AppModel) {
    _model = StateObject(wrappedValue: model)
  }

  public var body: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $section) { s in
        Text(s.rawValue).tag(s)
      }
      .navigationSplitViewColumnWidth(180)
    } detail: {
      detail
        .task { if model.phase == .idle { await model.scan() } }
        .sheet(isPresented: $confirming) {
          ConfirmSheet(bytes: model.selectedBytes) {
            confirming = false
            Task { await model.cleanSelected() }
          } cancel: { confirming = false }
        }
    }
  }

  @ViewBuilder private var detail: some View {
    switch section {
    case .recommended: recommended
    case .advanced:    ReviewTreeView(model: model)
    case .reports:     ReportsView()
    case .history:     HistoryView(model: model)
    }
  }

  @ViewBuilder private var recommended: some View {
    VStack(spacing: 16) {
      RingView(bytes: model.phase == .done ? model.lastFreed : model.selectedBytes,
               scanning: model.phase == .scanning)
      if model.phase == .done {
        Text(ReclaimLabel.done(bytes: model.lastFreed)).font(.title3)
        Text("\(ReclaimLabel.format(model.lastFreed)) · \(ReclaimLabel.reclaimHint)")
          .font(.caption).foregroundStyle(.secondary)
        Button("Put it all back") { Task { _ = await model.restoreLast() } }
      } else {
        Text(ReclaimLabel.hero(bytes: model.selectedBytes)).font(.title3)
        Button("Clean My Mac") { confirming = true }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(model.selectedBytes == 0)
        NavigationLink("Review what will be cleaned") { ReviewTreeView(model: model) }
          .font(.callout)
      }
    }
    .padding()
    .trust
  }
}

private extension View {
  // In-app trust line (spec §9): no telemetry, no network, open source.
  var trust: some View {
    safeAreaInset(edge: .bottom) {
      Text("No telemetry · No network · Open source (MIT)")
        .font(.caption2).foregroundStyle(.secondary).padding(8)
    }
  }
}
