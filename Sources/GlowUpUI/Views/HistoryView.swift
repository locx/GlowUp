import SwiftUI
import GlowKit

// History view: list all batches newest-first; per-row restore (spec §2A rule 4).
struct HistoryView: View {
  @ObservedObject var model: AppModel

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    let batches = model.batches
    let allTimeBytes = model.totalReclaimedAllTime

    VStack(alignment: .leading, spacing: 0) {
      PageHeader("History",
                 subtitle: allTimeBytes > 0
                   ? "Reclaimed \(ReclaimLabel.format(allTimeBytes)) all-time"
                   : "Every cleanup you run shows up here.")
      if batches.isEmpty {
        VStack(spacing: 12) {
          Spacer()
          Text("No cleanups yet — run Clean My Mac to see history here.")
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        List(batches) { batch in
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text(Self.dateFormatter.string(from: batch.date))
                .font(.body)
              Text("\(batch.items.count) item\(batch.items.count == 1 ? "" : "s") · \(ReclaimLabel.format(batch.totalBytes))")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            // Per-row restore; a fully-restored batch drops out of this list.
            Button("Put back") {
              Task { await model.restore(batch) }
            }
            .buttonStyle(.glowSecondaryCompact)
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
    .navigationTitle("History")
  }

}
