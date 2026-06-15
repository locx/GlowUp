import SwiftUI

// One restore-outcome label so a partial failure is always shown, never rounded to success.
struct RestoreFeedback: View {
  let result: AppModel.RestoreResult
  var font: Font = .body
  var body: some View {
    if result.failed == 0 {
      Text("Restored \(result.restored) item\(result.restored == 1 ? "" : "s") successfully.")
        .font(font).foregroundStyle(Color.brand)
    } else {
      Text("Restored \(result.restored); \(result.failed) couldn't be restored (Trash may have been emptied).")
        .font(font).foregroundStyle(Color.warning).multilineTextAlignment(.center)
    }
  }
}
