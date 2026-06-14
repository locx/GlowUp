import SwiftUI
import GlowKit

struct AboutPanel: View {
  var body: some View {
    VStack(spacing: 0) {
      PageHeader("About")
      VStack(spacing: 16) {
        BrandMark()
        Text("GlowUp").font(.largeTitle.weight(.semibold)).foregroundStyle(Color.textPrimary)
        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
          .font(.caption).foregroundStyle(Color.textSecondary)
        Text("A free, open-source macOS cleanup utility. Safety is the product; reclaim is the feature.")
          .multilineTextAlignment(.center).foregroundStyle(Color.textSecondary)
        Link("View on GitHub", destination: URL(string: "https://github.com/locx/GlowUp")!)
          .buttonStyle(.glowSecondary)
        Spacer()
      }
      .pagePadding()
    }
    .navigationTitle("About")
  }
}
