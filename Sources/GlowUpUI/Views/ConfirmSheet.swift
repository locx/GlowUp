import SwiftUI

struct ConfirmSheet: View {
  let bytes: Int64
  let confirm: () -> Void
  let cancel: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text(ReclaimLabel.confirmTitle(bytes: bytes)).font(.headline)
      Text("These are app caches and logs your Mac rebuilds automatically. "
         + "Nothing is deleted — everything goes to the Trash, and you can restore it anytime.")
        .multilineTextAlignment(.center).foregroundStyle(.secondary)
      HStack {
        Button("Not now", action: cancel)
        Button("Move to Trash", action: confirm).buttonStyle(.borderedProminent)
      }
    }
    .padding(24).frame(width: 420)
  }
}
