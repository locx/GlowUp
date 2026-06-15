import SwiftUI
import GlowKit

// A ring segment: one category arc with its proportional span.
struct RingSegment: Identifiable {
  let id: String       // category string
  let from: Double     // arc start (0–1)
  let to: Double       // arc end (0–1)
  let color: Color
}

// Arc shape for a single category segment.
private struct ArcShape: Shape {
  let startAngle: Angle
  let endAngle: Angle

  func path(in rect: CGRect) -> Path {
    var p = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    p.addArc(center: center, radius: radius,
             startAngle: startAngle, endAngle: endAngle,
             clockwise: false)
    return p
  }
}

// Concentric arc per category so the reclaim breakdown reads at a glance.
// Value-typed View — takes only the data it needs, no AppModel reference.
struct RingView: View {
  let categoryBytes: [CategorySlice]
  let totalBytes: Int64
  let phase: AppModel.Phase
  @Environment(\.accessibilityReduceMotion) private var reduce

  @State private var revealed: Int = 0
  @State private var animationAngle: Angle = .zero

  private let lineWidth: CGFloat = 28
  private let gapDegrees: Double = 1.5

  // Build arc spans proportional to per-category bytes.
  private var segments: [RingSegment] {
    let total = Double(categoryBytes.reduce(0) { $0 + $1.bytes })
    guard total > 0 else { return [] }
    var cursor: Double = 0
    let gapFraction = gapDegrees / 360.0
    return categoryBytes.compactMap { pair in
      let span = Double(pair.bytes) / total
      let gapped = max(0, span - gapFraction)
      guard gapped > 0 else { return nil }
      let seg = RingSegment(id: pair.category, from: cursor, to: cursor + gapped,
                            color: categoryTint(pair.category))
      cursor += span
      return seg
    }
  }

  var body: some View {
    // Built once per render; the arcs, reveal key, and stagger all share it.
    let segs = segments
    return ZStack {
      Circle()
        .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                                dash: phase == .idle ? [6, 4] : []))
        .opacity(phase == .scanning ? 0.3 : 0.5)

      switch phase {
      case .scanning:
        scanningRing
      case .results, .cleaning:
        ForEach(Array(segs.enumerated()), id: \.element.id) { idx, seg in
          arcView(seg: seg, visible: idx < revealed)
        }
      case .done:
        doneRing
      case .idle:
        EmptyView()
      }

      centerLabel
    }
    .frame(width: 220, height: 220)
    // Keyed on the inputs that change the arcs so a rescan restarts the reveal deterministically.
    .task(id: revealKey(segs)) { await reveal(count: segs.count) }
  }

  private func revealKey(_ segs: [RingSegment]) -> String {
    // Treat cleaning like results so the filled ring doesn't blank and re-stagger mid-clean.
    let p = phase == .cleaning ? "results" : "\(phase)"
    return "\(p)-\(totalBytes)-\(segs.map(\.id).joined(separator: ","))"
  }

  @ViewBuilder private var scanningRing: some View {
    Circle()
      .trim(from: 0, to: 0.25)
      .stroke(
        AngularGradient(colors: [Color.brand.opacity(0), .brand], center: .center),
        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
      )
      .rotationEffect(.degrees(-90))
      .rotationEffect(animationAngle)
      .animation(reduce ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false),
                 value: animationAngle)
  }

  @ViewBuilder private var doneRing: some View {
    Circle()
      .trim(from: 0, to: 1)
      .stroke(Color.brand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      .rotationEffect(.degrees(-90))
  }

  // Sits above the freed number in the center stack so the two never overlap.
  @ViewBuilder private var doneSeal: some View {
    let seal = Image(systemName: "checkmark.seal.fill")
      .font(.system(size: 26))
      .foregroundStyle(Color.brand)
    if #available(macOS 15, *) {
      seal.symbolEffect(.bounce)
    } else {
      seal
    }
  }

  @ViewBuilder private func arcView(seg: RingSegment, visible: Bool) -> some View {
    let start = Angle.degrees(seg.from * 360 - 90)
    let end   = Angle.degrees(seg.to * 360 - 90)
    ArcShape(startAngle: start, endAngle: end)
      .stroke(
        AngularGradient(
          colors: [seg.color.opacity(0.7), seg.color],
          center: .center,
          startAngle: start,
          endAngle: end
        ),
        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
      )
      .opacity(visible ? 1 : 0)
      .scaleEffect(visible ? 1 : 0.92)
      .animation(Motion.anim(reduce), value: visible)
  }

  @ViewBuilder private var centerLabel: some View {
    VStack(spacing: 4) {
      switch phase {
      case .scanning:
        Text("scanning…")
          .font(.heroNumber)
          .lineLimit(1).minimumScaleFactor(0.5)
          .foregroundStyle(Color.textSecondary)
      case .results, .cleaning:
        if totalBytes > 0 {
          // ReclaimLabel keeps the hero number consistent with every other size in the app and CLI.
          Text(ReclaimLabel.format(totalBytes))
            .font(.heroNumber)
            .lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText())
          Text("to free up").foregroundStyle(Color.textSecondary).font(.title3)
        } else {
          Text("Your Mac is already sparkling")
            .font(.title3).multilineTextAlignment(.center)
        }
      case .done:
        doneSeal
        Text(ReclaimLabel.format(totalBytes))
          .font(.heroNumber)
          .lineLimit(1).minimumScaleFactor(0.5)
          .contentTransition(.numericText())
        Text("Freed").foregroundStyle(Color.textSecondary).font(.title3)
      case .idle:
        EmptyView()
      }
    }
    .padding(lineWidth + 8)
  }

  // Stagger each segment ~60ms apart; cancellation (rescan) restarts cleanly, so the reveal never strands.
  @MainActor private func reveal(count: Int) async {
    // Advance a full turn each scan so the value changes and the spin restarts; skip when reduce-motion.
    if phase == .scanning, !reduce { animationAngle = .degrees(animationAngle.degrees + 360) }
    guard phase == .results || phase == .cleaning else { revealed = 0; return }
    if reduce {
      withAnimation(Motion.anim(reduce)) { revealed = count }
      return
    }
    revealed = 0
    for i in 0..<count {
      try? await Task.sleep(nanoseconds: 60_000_000)
      if Task.isCancelled { return }
      withAnimation(Motion.anim(reduce)) { revealed = i + 1 }
    }
  }
}
