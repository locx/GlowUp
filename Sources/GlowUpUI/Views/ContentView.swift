import SwiftUI
import GlowKit

// Main window: sidebar + section routing. Each section is its own view.
public struct ContentView: View {
  @ObservedObject private var model: AppModel
  @State private var confirming = false
  @State private var section: NavSection = .recommended
  @State private var iconSet = false
  // Set when Advanced is toggled so the Scan button re-arms (no auto-rescan).
  @State private var needsRescan = false

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView {
      Sidebar(selection: $section)
        .navigationSplitViewColumnWidth(180)
    } detail: {
      detailPanel
        // Set Dock icon once after launch (avoids premature set in bare SwiftPM execs).
        .onAppear {
          if !iconSet {
            iconSet = true
            NSApp.applicationIconImage = AppIconImage.make()
          }
        }
        // Auto-scan on launch (read-only); tiers come from the one policy point.
        .task {
          if model.phase == .idle {
            await model.scan(includeRisks: Risk.scanTiers(advanced: model.advanced))
          }
        }
        .sheet(isPresented: $confirming) {
          let selected = model.candidates.filter { model.selected.contains($0.id) }
          ConfirmSheet(selectedCandidates: selected, totalBytes: model.selectedBytes) {
            confirming = false
            Task { await model.cleanSelected() }
          } cancel: { confirming = false }
        }
    }
    .tint(.brand)
    .background(Color.graphite.ignoresSafeArea())
  }

  @ViewBuilder private var detailPanel: some View {
    Group {
      switch section {
      case .recommended:
        HeroPanel(model: model, confirming: $confirming, needsRescan: $needsRescan) {
          section = .advanced
        }
      case .advanced: ReviewTreeView(model: model)
      case .reports:  ReportsView(model: model)
      case .history:  HistoryView(model: model)
      case .about:    AboutPanel()
      }
    }
    // Toggling Advanced doesn't rescan — it re-arms the Scan button instead.
    .onChange(of: model.advanced) { _ in needsRescan = true }
    // Any scan (hero, review, or done) clears the re-arm, even one triggered from another view.
    .onChange(of: model.phase) { if $0 == .scanning { needsRescan = false } }
  }
}
