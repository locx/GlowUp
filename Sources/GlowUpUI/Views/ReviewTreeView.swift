import SwiftUI
import GlowKit

// Review tree — candidates grouped by app or category (grouping owned by AppModel).
struct ReviewTreeView: View {
  // Typed so a new permanent action can't ship a checkbox the Delete dispatch ignores.
  private enum PermanentAction: CaseIterable { case system, simulators }

  @ObservedObject var model: AppModel
  @State private var selectedPermanent: Set<PermanentAction> = []
  @State private var confirmPermanent = false
  @State private var permanentFailure: String?

  var body: some View {
    VStack(spacing: 0) {
      PageHeader("Review", subtitle: "What will be cleaned — untick anything you want to keep.")

      // Action area directly under the header (kept out of the window toolbar).
      HStack(spacing: 12) {
        Toggle("Advanced", isOn: $model.advanced)
          .toggleStyle(.glowCheckbox)
          .disabled(model.isBusy)
          .help("Include orphan scanners, project artifacts, and all risk tiers")
        Spacer()
        // Resets the selection to the pre-checked default tiers.
        Button("Select Defaults") { model.selected = model.defaultSelection }
        // Primary only when the selection has drifted from the defaults; otherwise a disabled secondary.
        .buttonStyle(model.canResetSelection ? GlowButtonStyle.glowPrimary : .glowSecondary)
        .disabled(!model.canResetSelection || model.isBusy)
        Button("Rescan") {
          Task { await model.scan(includeRisks: Risk.scanTiers(advanced: model.advanced)) }
        }
        .buttonStyle(.glowPrimary)
        .disabled(model.isBusy)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
      Divider()

      // Permanent group: these bypass the Trash and CAN'T be undone, so they're boxed off in red.
      // Hidden entirely when there's nothing permanent to remove — no empty red box.
      if model.advanced, !permanentIDs.isEmpty { permanentSection }

      // Hint banner when advanced is off — full-width, top-aligned icon+text.
      if !model.advanced {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle")
          Text("Turn on Advanced to also scan project build artifacts (node_modules, .build) and surface all risk tiers.")
            .font(.caption)
          Spacer()
        }
        .padding(12)
        .background(Color.brand.opacity(0.12))
        .foregroundStyle(Color.brand)
      }

      if model.phase == .scanning {
        // Scanning state: replace list with centered progress indicator.
        Spacer()
        ProgressView("Scanning…")
          .controlSize(.large)
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        Label("Recoverable · moves to Trash", systemImage: "arrow.uturn.backward")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.brand)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20).padding(.top, 10)
        List {
          ForEach(model.reviewGroups) { group in
            Section {
              ForEach(group.candidates) { c in row(c) }
            } header: {
              HStack(spacing: 8) {
                // Leading checkbox selects/deselects the whole group, matching the row toggles.
                Toggle("", isOn: groupBinding(group)).toggleStyle(.glowCheckboxBare)
                let g = glyph(for: group.category)
                Image(systemName: g.symbol).foregroundStyle(g.tint)
                Text(group.key)
                  .font(.headline)
                  .foregroundStyle(Color.textPrimary)
                Spacer()
                // Total aligns with the per-row size column.
                Text(ReclaimLabel.format(group.total))
                  .font(.caption).monospacedDigit()
                  .foregroundStyle(Color.textSecondary)
                  .frame(width: 76, alignment: .trailing)
              }
              .padding(.vertical, 4)
            }
          }
        }
        .scrollContentBackground(.hidden)

        // Footer: selected count, leading-aligned with row content.
        HStack {
          Text("\(model.selected.count) selected · \(ReclaimLabel.format(model.selectedBytes))")
            .font(.caption).foregroundStyle(Color.textSecondary)
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
      }
    }
    .task(id: model.advanced) {
      if model.advanced {
        // Independent probes (filesystem walk + simctl spawn); run them concurrently, not back to back.
        async let caches: Void = model.refreshSystemCaches()
        async let sims: Void = model.refreshUnavailableSimulators()
        _ = await (caches, sims)
      }
    }
    .alert("Permanently delete the selected items?", isPresented: $confirmPermanent) {
      Button("Delete", role: .destructive) {
        // Permanent actions have no Trash state to inspect afterwards — surface failures here.
        // The ops run off the main actor, so the result writes happen after the awaits, in order.
        let permanent = selectedPermanent
        Task { @MainActor in
          var failed: [String] = []
          if permanent.contains(.system), !(await model.cleanSystemCaches()) { failed.append("system caches") }
          if permanent.contains(.simulators), !(await model.removeUnavailableSimulators()) { failed.append("simulators") }
          permanentFailure = failed.isEmpty ? nil : "Couldn't complete: \(failed.joined(separator: ", "))."
          selectedPermanent = []
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(selectedPermanent.contains(.system)
           ? "This cannot be undone — there is no Trash for these. System caches will prompt for an administrator password."
           : "This cannot be undone — there is no Trash for these.")
    }
  }

  // Boxed-off, red group for actions that bypass the Trash — same leading-checkbox pattern as rows.
  @ViewBuilder private var permanentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Toggle("", isOn: allPermanentBinding).toggleStyle(.glowCheckboxBareDanger)
        Label("Permanent · cannot be undone", systemImage: "exclamationmark.octagon.fill")
          .font(.caption.weight(.semibold))
        Spacer()
        Button("Delete selected…") { confirmPermanent = true }
          // Danger only when something's selected to delete; otherwise a disabled secondary.
          .buttonStyle(selectedPermanent.isEmpty ? GlowButtonStyle.glowSecondary : .glowDanger)
          .disabled(selectedPermanent.isEmpty || model.isBusy)
      }
      if model.systemCacheBytes > 0 {
        permanentRow(.system, "System caches (admin): \(ReclaimLabel.format(model.systemCacheBytes))")
      }
      if model.hasUnavailableSimulators {
        permanentRow(.simulators, "Unavailable simulator devices")
      }
      if let permanentFailure {
        StatusMessage(permanentFailure, kind: .danger, leading: true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.danger.opacity(0.35), lineWidth: 1))
    .foregroundStyle(Color.danger)
    .padding(.horizontal, 20).padding(.vertical, 10)
  }

  private func permanentRow(_ id: PermanentAction, _ label: String) -> some View {
    HStack(spacing: 8) {
      Toggle("", isOn: permanentBinding(id)).toggleStyle(.glowCheckboxBareDanger)
      Text(label).font(.caption)
      Spacer()
    }
  }

  private var permanentIDs: [PermanentAction] {
    var ids: [PermanentAction] = []
    if model.systemCacheBytes > 0 { ids.append(.system) }
    if model.hasUnavailableSimulators { ids.append(.simulators) }
    return ids
  }

  private func permanentBinding(_ id: PermanentAction) -> Binding<Bool> {
    membership(id, in: $selectedPermanent)
  }

  // One Set-membership toggle serves both the model selection and the permanent rows.
  private func membership<T: Hashable>(_ id: T, in set: Binding<Set<T>>) -> Binding<Bool> {
    Binding(get: { set.wrappedValue.contains(id) },
            set: { on in
              if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            })
  }

  private var allPermanentBinding: Binding<Bool> {
    Binding(get: { !permanentIDs.isEmpty && permanentIDs.allSatisfy(selectedPermanent.contains) },
            set: { on in selectedPermanent = on ? Set(permanentIDs) : [] })
  }

  private func groupBinding(_ g: ReviewGroup) -> Binding<Bool> {
    Binding(get: { g.candidates.allSatisfy { model.selected.contains($0.id) } },
            set: { on in
              // One assignment, not one per row — each mutation republishes and re-totals.
              var sel = model.selected
              for c in g.candidates {
                if on { sel.insert(c.id) } else { sel.remove(c.id) }
              }
              model.selected = sel
            })
  }

  @ViewBuilder private func row(_ c: Candidate) -> some View {
    HStack(spacing: 10) {
      Toggle("", isOn: binding(for: c)).toggleStyle(.glowCheckboxBare)
      appIcon(for: c)
      VStack(alignment: .leading, spacing: 2) {
        Text(c.url.lastPathComponent).font(.body).foregroundStyle(Color.textPrimary).lineLimit(1)
        Text(c.url.path).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // Fixed-width tag and size columns so every row lines up.
      RiskCapsule(risk: c.risk).frame(width: 112, alignment: .leading)
      Text(ReclaimLabel.format(model.sizes[c.id] ?? 0))
        .monospacedDigit().font(.body).foregroundStyle(Color.textSecondary)
        .frame(width: 76, alignment: .trailing)
    }
    .padding(.vertical, 4)
    .listRowBackground(Color.clear)
  }

  // Category SF Symbol — avoids synchronous NSWorkspace icon I/O on the main thread per row.
  @ViewBuilder private func appIcon(for c: Candidate) -> some View {
    let g = glyph(for: c.category)
    Image(systemName: g.symbol)
      .frame(width: 20, height: 20)
      .foregroundStyle(g.tint)
  }

  private func binding(for c: Candidate) -> Binding<Bool> {
    membership(c.id, in: $model.selected)
  }
}

// Color + a text label, never color alone, so risk reads without color vision.
struct RiskCapsule: View {
  let risk: Risk
  var body: some View {
    HStack(spacing: 3) {
      Circle().fill(color(for: risk)).frame(width: 6, height: 6)
      Text(label)
        .font(.caption2.weight(.semibold))
        .tracking(0.5)
        .textCase(.uppercase)
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 7).padding(.vertical, 3)
    .background(color(for: risk).opacity(0.15), in: Capsule())
    .foregroundStyle(color(for: risk))
  }
  private var label: String { risk.displayName }
}
