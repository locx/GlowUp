import SwiftUI
import GlowKit

// The Recommended landing: hero ring, legend, and the primary action row.
struct HeroPanel: View {
  @ObservedObject var model: AppModel
  @Binding var confirming: Bool
  @Binding var needsRescan: Bool
  var onReview: () -> Void

  // Bytes shown in the ring: lastFreed on done, selectedBytes otherwise.
  private var ringBytes: Int64 {
    model.phase == .done ? model.lastFreed : model.selectedBytes
  }

  // Folded once so the ring arcs and the legend rows share identical slices and colors.
  private var slices: [CategorySlice] { CandidateGrouping.forDisplay(model.categoryBytes) }

  var body: some View {
    ScrollView {
      HStack {
        Spacer(minLength: 0)
        VStack(spacing: 20) {
          if model.catalogLoadFailed {
            Text("Couldn't load the cleanup catalog — results may be incomplete.")
              .font(.callout).foregroundStyle(Color.warning)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          // Some directories couldn't be read, so an incomplete result isn't mistaken for "clean".
          if model.phase == .results, !model.scanDiagnostics.isEmpty {
            Text("Some directories couldn't be read — results may be incomplete.")
              .font(.callout).foregroundStyle(Color.warning)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          RingView(categoryBytes: slices, totalBytes: ringBytes, phase: model.phase)
          heroLabel

          // An empty scan with no disk access means "limited", not "already clean".
          if model.phase == .results, model.candidates.isEmpty, model.limitedAccess {
            OnboardingView()
          }
          // Legend: what each ring colour is and its share of the reclaimable total.
          if model.phase == .results || model.phase == .cleaning, !slices.isEmpty {
            CategoryBar(items: slices).frame(maxWidth: 360)
          }

          actionRow

          if model.phase != .done && !model.candidates.isEmpty {
            Button("Review what will be cleaned ›", action: onReview)
              .buttonStyle(.plain).font(.callout).foregroundStyle(Color.brand)
          }
          if model.phase == .done { doneExtras }
          trustPills
        }
        .frame(maxWidth: 520)
        Spacer(minLength: 0)
      }
      .pagePadding()
    }
  }

  @ViewBuilder private var heroLabel: some View {
    switch model.phase {
    case .scanning:
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Looking through caches and logs…")
          .font(.title3).foregroundStyle(Color.textSecondary)
      }
    case .results, .cleaning:
      Text(model.selectedBytes > 0 ? ReclaimLabel.hero(bytes: model.selectedBytes)
                                    : "Your Mac is already sparkling")
        .font(.title3).foregroundStyle(Color.textPrimary)
    case .done:
      Text("· \(ReclaimLabel.reclaimHint)")
        .font(.caption).foregroundStyle(Color.textSecondary)
    case .idle:
      EmptyView()
    }
  }

  @ViewBuilder private var actionRow: some View {
    HStack(spacing: 12) {
      if model.phase == .done {
        Button("Put it all back") { Task { _ = await model.restoreLast() } }
          .buttonStyle(.glowSecondary)
          .disabled(!model.canRestoreLast)
          .keyboardShortcut("z", modifiers: .command)
      } else {
        Button("Clean My Mac") { confirming = true }
          .buttonStyle(.glowPrimary)
          .disabled(model.selectedBytes == 0 || model.phase == .scanning)
          .keyboardShortcut(.return, modifiers: .command)
      }
      scanButton
      Toggle("Advanced", isOn: $model.advanced)
        .toggleStyle(.checkbox)
        .help("Include orphan scanners, project artifacts, and all risk tiers")
    }
  }

  @ViewBuilder private var scanButton: some View {
    let scan = Button(needsRescan ? "Rescan" : "Scan") {
      needsRescan = false
      Task { await model.scan(includeRisks: Risk.scanTiers(advanced: model.advanced)) }
    }
    .disabled(model.phase == .scanning || model.phase == .cleaning)
    // Stands out after an Advanced toggle so the user knows to rescan.
    if needsRescan { scan.buttonStyle(.glowPrimary) } else { scan.buttonStyle(.glowSecondary) }
  }

  @ViewBuilder private var doneExtras: some View {
    VStack(spacing: 8) {
      // After a clean, emptying the Trash is the reclaim CTA — promote it.
      Button("Empty Trash") { model.emptyTrash() }
        .buttonStyle(.glowPrimary)
        .disabled(model.trashCount == 0)
      if let r = model.lastRestore {
        RestoreFeedback(result: r, font: .caption)
      }
      if model.lastCleanFailures > 0 {
        Text("\(model.lastCleanFailures) item\(model.lastCleanFailures == 1 ? "" : "s") couldn't be moved to Trash.")
          .font(.caption).foregroundStyle(Color.warning)
      }
      if let warning = model.lastCleanWarning {
        Text(warning).font(.caption).foregroundStyle(Color.warning)
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
      Link("View on GitHub", destination: URL(string: "https://github.com/locx/GlowUp")!)
        .font(.caption2).foregroundStyle(Color.brand)
    }
    .fixedSize(horizontal: false, vertical: true)
    .multilineTextAlignment(.center)
  }
}
