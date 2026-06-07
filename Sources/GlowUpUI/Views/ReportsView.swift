import SwiftUI

// Un-actionable by design (spec §2A rule 1): no checkboxes here.
struct ReportsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Reports — things to look at yourself. GlowUp won't touch these.")
        .font(.headline)
      Text("Large & old files, Trash size, APFS snapshots, and /Library system "
         + "items appear here as read-only guidance.")
        .foregroundStyle(.secondary)
      Text("Protected files are never listed here.").font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
    .padding().frame(maxWidth: .infinity, alignment: .leading)
    .navigationTitle("Reports")
  }
}
