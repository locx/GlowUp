import SwiftUI
import AppKit
import GlowKit

// Large-file findings (the user's own data): selectable for explicit, recoverable Trash, never auto-cleaned.
struct ReportsView: View {
  @ObservedObject var model: AppModel
  @State private var selected: Set<String> = []
  @State private var confirmTrash = false

  // Always scanned; shown locked so the user adds extras without losing the baseline.
  private let defaultFolders = AdvancedScan.defaultReportFolderNames

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PageHeader("Reports",
                 subtitle: "Large files to review — select any to move to the Trash (you can put them back).")

      foldersSection
      Divider()

      if model.reports.isEmpty {
        Spacer()
        EmptyState(symbol: "doc.text.magnifyingglass",
                   text: "Nothing over 100 MB in your scanned folders right now. "
                       + "Large files worth reviewing yourself show up here.")
        Spacer()
      } else {
        HStack(spacing: 8) {
          Toggle("", isOn: allSelectedBinding).toggleStyle(.glowCheckboxBare)
          Text("Select all").font(.caption).foregroundStyle(Color.textSecondary)
          Spacer()
          Button("Move to Trash") { confirmTrash = true }
            .buttonStyle(selected.isEmpty ? GlowButtonStyle.glowSecondary : .glowPrimary)
            .disabled(selected.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        Divider()

        List(model.reports) { report in
          HStack(spacing: 10) {
            Toggle("", isOn: rowBinding(report.id)).toggleStyle(.glowCheckboxBare)
            Image(systemName: "doc.fill")
              .frame(width: 20, height: 20)
              .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(report.url.lastPathComponent).font(.body).lineLimit(1)
              RevealPathLabel(url: report.url)
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
    .alert("Move \(selected.count) file\(selected.count == 1 ? "" : "s") to the Trash?",
           isPresented: $confirmTrash) {
      Button("Move to Trash") {
        let ids = selected
        Task { await model.trashReports(ids); selected = [] }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("They go to the Trash — put them back anytime from History.")
    }
    // A rescan or folder change reshuffles the list; a stale selection would mis-target the trash.
    .onChange(of: model.reports) { _ in selected = [] }
  }

  private func rowBinding(_ id: String) -> Binding<Bool> {
    Binding(get: { selected.contains(id) },
            set: { on in if on { selected.insert(id) } else { selected.remove(id) } })
  }

  private var allSelectedBinding: Binding<Bool> {
    Binding(get: { !model.reports.isEmpty && selected.count == model.reports.count },
            set: { on in selected = on ? Set(model.reports.map(\.id)) : [] })
  }

  @ViewBuilder private var foldersSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("FOLDERS").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
        Spacer()
        Button("Rescan") { Task { await model.refreshReports() } }
          .buttonStyle(.glowSecondary).disabled(model.isBusy)
        Button("Add folder…") { pickFolder() }.buttonStyle(.glowPrimary)
      }
      ForEach(defaultFolders, id: \.self) {
        folderRow(url: model.reportFolderURL(named: $0), name: $0, removable: nil)
      }
      ForEach(model.reportFolders, id: \.path) {
        folderRow(url: $0, name: $0.lastPathComponent, removable: $0)
      }
    }
    .padding(.horizontal, 20).padding(.vertical, 10)
  }

  private func folderRow(url: URL, name: String, removable: URL?) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "folder").foregroundStyle(Color.textSecondary).frame(width: 20)
      Button { RevealInFinder.reveal(url) } label: {
        Text(name).font(.body).foregroundStyle(Color.textPrimary).lineLimit(1)
      }
      .buttonStyle(.plain).help("Reveal in Finder")
      Spacer()
      if let url = removable {
        Button { model.removeReportFolder(url) } label: {
          Image(systemName: "xmark.circle").foregroundStyle(Color.brand)
        }
        .buttonStyle(.plain).help("Stop scanning this folder")
      } else {
        Text("default").font(.caption).foregroundStyle(Color.textSecondary)
      }
    }
  }

  // Native directory picker; non-sandboxed, so the chosen path stays readable without bookmarks.
  private func pickFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Choose"
    panel.message = "Choose a folder to scan for large files"
    if panel.runModal() == .OK { panel.urls.forEach(model.addReportFolder) }
  }
}
