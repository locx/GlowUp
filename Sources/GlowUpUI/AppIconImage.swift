import AppKit

/// Renders the GlowUp brand icon without any asset catalog.
/// Emerald squircle background with a white "sparkles" SF Symbol centred at 55 % scale.
public enum AppIconImage {
  public static func make(size: CGFloat = 1024) -> NSImage {
    let canvas = NSSize(width: size, height: size)
    return NSImage(size: canvas, flipped: false) { rect in
      // Squircle background in emerald (#10B981).
      let emerald = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1)
      emerald.setFill()
      let radius = rect.width * 0.2237   // Apple icon corner-radius ratio
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

      // White "sparkles" SF Symbol at ~55 % of canvas, centred.
      let symbolSize = size * 0.55
      let symbolRect = CGRect(
        x: (size - symbolSize) / 2,
        y: (size - symbolSize) / 2,
        width: symbolSize,
        height: symbolSize
      )
      if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
        let tinted = symbol.withSymbolConfiguration(cfg) ?? symbol
        // Tint white by compositing into a white-filled offscreen image.
        let white = NSImage(size: NSSize(width: symbolSize, height: symbolSize), flipped: false) { r in
          NSColor.white.setFill()
          r.fill()
          tinted.draw(in: r,
                      from: .zero,
                      operation: .destinationIn,
                      fraction: 1)
          return true
        }
        white.draw(in: symbolRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1)
      }
      return true
    }
  }
}
