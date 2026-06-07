import SwiftUI

// FDA value-first (spec §6): show a number, then ask for Full Disk Access.
struct OnboardingView: View {
  let reclaimableHint: String
  var body: some View {
    VStack(spacing: 16) {
      Text("Limited access — grant Full Disk Access to reclaim \(reclaimableHint) more")
        .font(.headline).multilineTextAlignment(.center)
      Link("Open Full Disk Access settings",
           destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    .padding(24)
  }
}
