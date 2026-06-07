import SwiftUI

struct HistoryView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 12) {
      Text("History").font(.headline)
      Button("Put it all back") { Task { _ = await model.restoreLast() } }
      Text("Restores your most recent cleanup from the Trash.")
        .font(.caption).foregroundStyle(.secondary)
      Spacer()
    }
    .padding().navigationTitle("History")
  }
}
