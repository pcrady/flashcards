import AppKit

// Renders the språk app icon: midnight squircle, aurora glow, stars, and
// a serif italic "å" glyph. Outputs a 1024x1024 PNG.

func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat) -> NSColor {
  NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
          blue: CGFloat(b) / 255, alpha: a)
}

let size = 1024
let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824x824 squircle centered in the 1024 canvas.
let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: 186, yRadius: 186)

NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()

// Midnight background, slightly lighter at the top.
NSGradient(colors: [rgba(24, 32, 58, 1), rgba(8, 12, 24, 1)])!
  .draw(in: iconRect, angle: -90)

// Aurora: soft radial glows sweeping across the upper half.
let glows: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
  (rgba(43, 228, 162, 0.60), 250, 660, 380),  // mint
  (rgba(78, 168, 245, 0.55), 470, 750, 400),  // ice blue
  (rgba(185, 92, 244, 0.55), 690, 700, 380),  // violet
  (rgba(240, 80, 158, 0.45), 880, 560, 340),  // magenta
  (rgba(43, 228, 162, 0.18), 300, 220, 300),  // faint mint echo, low
]
for (color, x, y, r) in glows {
  let clear = color.withAlphaComponent(0)
  NSGradient(colors: [color, clear])!.draw(
    fromCenter: NSPoint(x: x, y: y), radius: 0,
    toCenter: NSPoint(x: x, y: y), radius: r,
    options: [])
}

// Starfield: seeded LCG so the icon is reproducible.
var seed: UInt64 = 0x5eed_5eed
func rand() -> CGFloat {
  seed = seed &* 6364136223846793005 &+ 1442695040888963407
  return CGFloat((seed >> 33) % 10_000) / 10_000
}
for _ in 0..<70 {
  let x = 110 + rand() * 800
  let y = 320 + rand() * 580
  let r = 1.2 + rand() * 2.4
  rgba(237, 241, 251, 0.25 + rand() * 0.55).setFill()
  NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    .fill()
}

// The glyph: serif italic å, softly shadowed so it lifts off the aurora.
let font = NSFont(name: "Georgia-BoldItalic", size: 620)
  ?? NSFont.systemFont(ofSize: 620, weight: .bold)
let shadow = NSShadow()
shadow.shadowColor = rgba(5, 8, 18, 0.85)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -10)
let glyph = NSAttributedString(string: "å", attributes: [
  .font: font,
  .foregroundColor: rgba(237, 241, 251, 1),
  .shadow: shadow,
])
let gSize = glyph.size()
glyph.draw(at: NSPoint(x: (1024 - gSize.width) / 2 - 10,
                       y: (1024 - gSize.height) / 2 - 30))

NSGraphicsContext.current?.restoreGraphicsState()

// Hairline edge so the squircle reads crisply against light backgrounds.
rgba(120, 140, 190, 0.35).setStroke()
let edge = NSBezierPath(roundedRect: iconRect.insetBy(dx: 1, dy: 1),
                        xRadius: 185, yRadius: 185)
edge.lineWidth = 2
edge.stroke()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
