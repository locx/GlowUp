#!/usr/bin/env swift
// Generates GlowUp.iconset PNGs and compiles AppIcon.icns.
// Usage: swift packaging/make-icon.swift   (run from repo root)
import AppKit

// Inline drawing (mirrors AppIconImage.make) — no cross-module import available in a loose script.
func makeIcon(size: CGFloat) -> NSImage {
  let canvas = NSSize(width: size, height: size)
  return NSImage(size: canvas, flipped: false) { rect in
    let emerald = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1)
    emerald.setFill()
    let radius = rect.width * 0.2237
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

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
      let white = NSImage(size: NSSize(width: symbolSize, height: symbolSize), flipped: false) { r in
        NSColor.white.setFill()
        r.fill()
        tinted.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
        return true
      }
      white.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    return true
  }
}

func writePNG(_ image: NSImage, to path: String) {
  guard let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let png = bitmap.representation(using: .png, properties: [:])
  else {
    fputs("Failed to render PNG for \(path)\n", stderr)
    exit(1)
  }
  let url = URL(fileURLWithPath: path)
  do {
    try png.write(to: url)
  } catch {
    fputs("Write error \(path): \(error)\n", stderr)
    exit(1)
  }
}

// Resolve iconset directory relative to this script's location.
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconsetDir = scriptURL.appendingPathComponent("GlowUp.iconset").path

do {
  try FileManager.default.createDirectory(atPath: iconsetDir,
                                          withIntermediateDirectories: true)
} catch {
  fputs("Cannot create iconset dir: \(error)\n", stderr)
  exit(1)
}

// Required iconset sizes: (logical, scale).
let sizes: [(Int, Int)] = [
  (16, 1), (16, 2),
  (32, 1), (32, 2),
  (128, 1), (128, 2),
  (256, 1), (256, 2),
  (512, 1), (512, 2),
]

for (logical, scale) in sizes {
  let pixels = CGFloat(logical * scale)
  let img = makeIcon(size: pixels)
  let name = scale == 1
    ? "icon_\(logical)x\(logical).png"
    : "icon_\(logical)x\(logical)@2x.png"
  let dest = "\(iconsetDir)/\(name)"
  writePNG(img, to: dest)
  print("Written \(dest)")
}

print("Done. Now run: iconutil -c icns packaging/GlowUp.iconset -o packaging/AppIcon.icns")
