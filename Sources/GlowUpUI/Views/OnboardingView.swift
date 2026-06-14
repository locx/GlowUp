import SwiftUI

// Shown when a scan finds nothing AND Full Disk Access is off, so "nothing found" isn't mistaken for clean.
struct OnboardingView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Limited access — grant Full Disk Access so GlowUp can find more to clean.")
        .font(.headline).multilineTextAlignment(.center)
      Link("Open Full Disk Access settings",
           destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    .padding(24)
  }
}
