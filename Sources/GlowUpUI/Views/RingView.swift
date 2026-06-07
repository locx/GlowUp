import SwiftUI

// Hero gauge; fills proportionally to reclaimable bytes.
struct RingView: View {
  let bytes: Int64
  let scanning: Bool

  var body: some View {
    ZStack {
      Circle().stroke(.quaternary, style: StrokeStyle(lineWidth: 24, lineCap: .round))
      Circle()
        .trim(from: 0, to: scanning ? 0.15 : 0.8)
        .stroke(Color.green, style: StrokeStyle(lineWidth: 24, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: bytes)
      VStack(spacing: 4) {
        Text(scanning ? "scanning…" : ReclaimLabel.format(bytes))
          .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
        if !scanning { Text("to free up").foregroundStyle(.secondary) }
      }
    }
    .frame(width: 240, height: 240)
    .padding()
  }
}
