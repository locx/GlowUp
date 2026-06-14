import SwiftUI
import GlowKit

// Reports: un-actionable by design (spec §2A rule 1). No checkboxes — ever.
struct ReportsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PageHeader("Reports", subtitle: "Things to look at yourself — GlowUp won't touch these.")

      // Action area directly under the header.
      HStack {
        Text("Already in Trash — empty to free space.")
          .font(.caption).foregroundStyle(Color.textSecondary)
        Spacer()
        Button("Empty Trash") { model.emptyTrash() }
          .buttonStyle(.glowPrimary)
          .disabled(model.trashCount == 0)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
      Divider()

      if model.reports.isEmpty {
        Spacer()
        Text("No large files found in Downloads or Movies.")
          .foregroundStyle(Color.textSecondary)
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        List(model.reports) { report in
          HStack {
            Image(systemName: "doc.fill").foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(report.url.lastPathComponent).font(.body).lineLimit(1)
              Text(report.url.path).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
            }
            Spacer()
            Text(ReclaimLabel.format(report.bytes)).monospacedDigit().foregroundStyle(Color.textSecondary)
          }
          .padding(.vertical, 2)
          .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { model.refreshTrash() }
    .navigationTitle("Reports")
  }
}
