import SwiftUI

// Shown when a scan finds nothing AND Full Disk Access is off, so "nothing found" isn't mistaken for clean.
struct OnboardingView: View {
  var body: some View {
    VStack(spacing: 16) {
      EmptyState(symbol: "lock.shield",
                 text: "Limited access — grant Full Disk Access so GlowUp can find more to clean.")
      if let url = AppLinks.fullDiskAccessSettings {
        Link("Open Full Disk Access settings", destination: url)
          .buttonStyle(.glowSecondary)
      }
    }
    .padding(24)
  }
}
