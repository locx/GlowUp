import SwiftUI
import GlowKit

// Adds one consequential warning line when non-safe items are selected, so the copy is never misleading.
struct ConfirmSheet: View {
  let selectedCandidates: [Candidate]
  let totalBytes: Int64
  let confirm: () -> Void
  let cancel: () -> Void

  private var nonSafe: [Candidate] { selectedCandidates.filter { $0.risk != .safe } }

  private var nonSafeCategories: String {
    Set(nonSafe.map(\.category)).sorted().joined(separator: ", ")
  }

  var body: some View {
    VStack(spacing: 16) {
      Text(ReclaimLabel.confirmTitle(bytes: totalBytes)).font(.headline)
      Text("These are app caches and logs your Mac rebuilds automatically. "
         + "Nothing is deleted — everything goes to the Trash, and you can restore it anytime.")
        .multilineTextAlignment(.center).foregroundStyle(.secondary)
      if !nonSafe.isEmpty {
        // Itemize non-safe items so the copy honestly reflects the full selection.
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(Color.warning).font(.callout)
          Text("Includes \(nonSafe.count) item\(nonSafe.count == 1 ? "" : "s") "
             + "that aren't just caches (\(nonSafeCategories)).")
            .font(.callout).foregroundStyle(Color.warning).multilineTextAlignment(.leading)
        }
        .padding(10)
        .background(Color.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      }
      HStack {
        Button("Not now", action: cancel).buttonStyle(.glowSecondary)
        Button("Move to Trash", action: confirm).buttonStyle(.glowPrimary)
      }
    }
    .padding(24).frame(width: 420)
  }
}
