import SwiftUI
import GlowKit

// Batches newest-first; only the latest batch still in the Trash can be restored, the rest are forget-only.
struct HistoryView: View {
  @ObservedObject var model: AppModel
  @State private var selected: Set<String> = []

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    let batches = model.batches
    let allTimeBytes = model.totalReclaimedAllTime
    let restorableID = model.latestRestorableBatch?.id

    VStack(alignment: .leading, spacing: 0) {
      PageHeader("History",
                 subtitle: allTimeBytes > 0
                   ? "Reclaimed \(ReclaimLabel.format(allTimeBytes)) all-time"
                   : "Every cleanup you run shows up here.")
      if batches.isEmpty {
        Spacer()
        EmptyState(symbol: "clock.arrow.circlepath",
                   text: "No cleanups yet — run Clean My Mac to see history here.")
          .padding()
        Spacer()
      } else {
        // Select-all + bulk forget; removing a record only drops it from this list, never the Trash.
        HStack(spacing: 8) {
          Toggle("", isOn: allSelectedBinding(batches)).toggleStyle(.glowCheckboxBare)
          Text("Select all").font(.caption).foregroundStyle(Color.textSecondary)
          Spacer()
          Button("Remove selected") {
            model.forgetHistory(selected)
            selected = []
          }
          .buttonStyle(selected.isEmpty ? GlowButtonStyle.glowSecondary : .glowPrimary)
          .disabled(selected.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        Divider()

        List(batches) { batch in
          HStack(spacing: 12) {
            Toggle("", isOn: rowBinding(batch.id)).toggleStyle(.glowCheckboxBare)
            VStack(alignment: .leading, spacing: 3) {
              Text(Self.dateFormatter.string(from: batch.date))
                .font(.body)
              Text("\(batch.items.count) item\(batch.items.count == 1 ? "" : "s") · \(ReclaimLabel.format(batch.totalBytes))")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            // Only the newest batch whose files are still in the Trash can be put back.
            if batch.id == restorableID {
              Button("Put back") { Task { await model.restore(batch) } }
                .buttonStyle(.glowSecondary)
                .disabled(model.isBusy)
            }
          }
          .padding(.vertical, 2)
          .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
      }

      // Restore outcome feedback.
      if let r = model.lastRestore {
        Divider()
        RestoreFeedback(result: r)
          .padding()
      }
    }
    .onAppear { model.refreshHistory() }
  }

  private func rowBinding(_ id: String) -> Binding<Bool> {
    Binding(get: { selected.contains(id) },
            set: { on in if on { selected.insert(id) } else { selected.remove(id) } })
  }

  private func allSelectedBinding(_ batches: [CleanupBatch]) -> Binding<Bool> {
    Binding(get: { !batches.isEmpty && selected.count == batches.count },
            set: { on in selected = on ? Set(batches.map(\.id)) : [] })
  }
}
