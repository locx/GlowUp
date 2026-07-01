import SwiftUI
import GlowKit

// The Recommended landing: hero ring, legend, and the primary action row.
// Fixed-width, top-anchored column so phase changes never re-center or re-width the layout.
struct HeroPanel: View {
  @ObservedObject var model: AppModel
  @Binding var confirming: Bool
  @Binding var needsRescan: Bool
  var onReview: () -> Void
  @State private var showDiagnostics = false

  // One width and one rhythm constant; every gap is sectionGap or a tighter half.
  private let contentWidth: CGFloat = 480
  private let sectionGap: CGFloat = 28

  // Bytes shown in the ring: lastFreed on done, selectedBytes otherwise.
  private var ringBytes: Int64 {
    model.phase == .done ? model.lastFreed : model.selectedBytes
  }

  // Folded once so the ring arcs and the legend rows share identical slices and colors.
  private var slices: [CategorySlice] { CandidateGrouping.forDisplay(model.categoryBytes) }

  var body: some View {
    GeometryReader { proxy in
    // Bind once: forDisplay does three passes and the body reads it for the ring, the gate, and the bar.
    let slices = self.slices
    ScrollView {
      VStack(spacing: sectionGap) {
        banners

        RingView(categoryBytes: slices, totalBytes: ringBytes, phase: model.phase,
                 limited: model.limitedAccess)

        // Always reserve the sub-line's slot so the scanning message appears without shifting the layout.
        subLabel.frame(height: 24)

        // An empty scan with no disk access means "limited", not "already clean".
        if model.phase == .results, model.candidates.isEmpty, model.limitedAccess {
          OnboardingView()
        }
        // Legend stays visible through scanning (data persists from the last scan) so a rescan
        // doesn't remove it and shove the buttons around.
        if model.phase != .idle, !slices.isEmpty {
          CategoryBar(items: slices)
        }

        // Primary action block: the clean/scan pills with the Advanced toggle beneath them.
        VStack(spacing: sectionGap / 2) {
          actionRow
          Toggle("Advanced", isOn: $model.advanced)
            .toggleStyle(.glowCheckbox)
            .disabled(model.isBusy)
            .help("Include orphan scanners, project artifacts, and all risk tiers")
        }

        secondaryActions
        trustPills
      }
      .frame(width: contentWidth)
      .padding(.vertical, 32)
      // Fill at least the viewport so the column centers vertically instead of pinning to the top.
      .frame(maxWidth: .infinity, minHeight: proxy.size.height)
    }
    }
  }

  // Grouped so any present banner sits at the top of the column; each only renders when it applies.
  @ViewBuilder private var banners: some View {
    if model.catalogLoadFailed {
      StatusMessage("Couldn't load the cleanup catalog — results may be incomplete.")
    }
    // Some directories couldn't be read, so an incomplete result isn't mistaken for "clean".
    if model.phase == .results, !model.scanDiagnostics.isEmpty {
      Button { showDiagnostics = true } label: {
        StatusMessage("Some directories couldn't be read — results may be incomplete.")
      }
      .buttonStyle(.plain)
      .help("Click to see which directories couldn't be read")
      .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) { diagnosticsPopover }
    }
  }

  // Sub-line under the ring; the reclaim amount itself lives in the ring center, never repeated here.
  @ViewBuilder private var subLabel: some View {
    switch model.phase {
    case .scanning:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Looking through caches and logs…")
          .font(.callout).foregroundStyle(Color.textSecondary).lineLimit(1)
      }
    case .done:
      Text(ReclaimLabel.reclaimHint)
        .font(.caption).foregroundStyle(Color.textSecondary)
    case .results, .cleaning, .idle:
      // Clear placeholder (not EmptyView) so the reserved slot keeps its height when there's no text.
      Color.clear
    }
  }

  @ViewBuilder private var actionRow: some View {
    HStack(spacing: 12) {
      if model.phase == .done {
        Button("Put it all back") { Task { _ = await model.restoreLast() } }
          .buttonStyle(.glowSecondary)
          .disabled(model.isBusy || !model.canRestoreLast)
          .keyboardShortcut("z", modifiers: .command)
      } else {
        Button("Clean My Mac") { confirming = true }
          // Primary only when there's a selection to clean; otherwise a disabled secondary.
          .buttonStyle(model.canClean ? GlowButtonStyle.glowPrimary : .glowSecondary)
          .disabled(!model.canClean || model.isBusy)
          .keyboardShortcut(.return, modifiers: .command)
      }
      scanButton
    }
  }

  @ViewBuilder private var scanButton: some View {
    let scan = Button(needsRescan ? "Rescan" : "Scan") {
      needsRescan = false
      Task { await model.scan(includeRisks: Risk.scanTiers(advanced: model.advanced)) }
    }
    .disabled(model.isBusy)
    // Stands out after an Advanced toggle so the user knows to rescan.
    if needsRescan { scan.buttonStyle(.glowPrimary) } else { scan.buttonStyle(.glowSecondary) }
  }

  // Reclaim follow-up beneath the action block: Empty Trash after a clean, the review link before it.
  @ViewBuilder private var secondaryActions: some View {
    if model.phase == .done {
      doneExtras
    } else if !model.candidates.isEmpty {
      Button("Review what will be cleaned ›", action: onReview)
        .buttonStyle(.plain).font(.callout).foregroundStyle(Color.brand)
    }
  }

  @ViewBuilder private var doneExtras: some View {
    VStack(spacing: sectionGap / 2) {
      // After a clean, emptying the Trash is the reclaim CTA — promote it.
      Button("Empty Trash") { model.emptyTrash() }
        // Primary only when there's something to empty; otherwise a disabled secondary (no valid action).
        .buttonStyle(model.canEmptyTrash ? GlowButtonStyle.glowPrimary : .glowSecondary)
        .disabled(!model.canEmptyTrash || model.isBusy)
      if let r = model.lastRestore {
        RestoreFeedback(result: r, font: .caption)
      }
      if model.lastCleanFailures > 0 {
        StatusMessage("\(model.lastCleanFailures) item\(model.lastCleanFailures == 1 ? "" : "s") couldn't be moved to Trash.")
      }
      if let warning = model.lastCleanWarning {
        StatusMessage(warning)
      }
    }
  }

  @ViewBuilder private var trustPills: some View {
    HStack(spacing: 16) {
      Text("No telemetry · No network · Open source (MIT)")
        .font(.caption2).foregroundStyle(Color.textSecondary)
      Button("View the catalog") {
        if let url = model.catalogURL { NSWorkspace.shared.open(url) }
      }
      .font(.caption2).buttonStyle(.plain).foregroundStyle(Color.brand)
      if let url = AppLinks.gitHub {
        Link("View on GitHub", destination: url)
          .font(.caption2).foregroundStyle(Color.brand)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .multilineTextAlignment(.center)
  }

  // Lists the unreadable directories so the user can see exactly what the scan skipped.
  @ViewBuilder private var diagnosticsPopover: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Directories that couldn't be read").font(.headline)
      Text("Grant Full Disk Access to include these in the scan.")
        .font(.caption).foregroundStyle(Color.textSecondary)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(model.scanDiagnostics, id: \.self) { url in
            RevealPathLabel(url: url, font: .caption, monospaced: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 220)
    }
    .padding(16)
    .frame(width: 420)
  }
}
