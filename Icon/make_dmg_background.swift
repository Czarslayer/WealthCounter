// Draws the DMG window background at 1x and 2x.
// Usage: swift Icon/make_dmg_background.swift <output-dir>
// Layout must match Icon/dmg_settings.py: 640×450 background, icons centred at (160, 230) and (480, 230).
import AppKit

let width = 640.0, height = 450.0
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

let green = NSColor(red: 0.04, green: 0.37, blue: 0.27, alpha: 1)
let mint = NSColor(red: 0.13, green: 0.77, blue: 0.57, alpha: 1)
let gold = NSColor(red: 0.99, green: 0.78, blue: 0.27, alpha: 1)

func draw(in ctx: CGContext) {
    // Soft off-white → mint wash
    let bg = NSGradient(colors: [NSColor(red: 0.98, green: 0.995, blue: 0.99, alpha: 1),
                                 NSColor(red: 0.90, green: 0.97, blue: 0.94, alpha: 1)])!
    bg.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    // Gentle glows behind each icon
    for x in [160.0, 480.0] {
        let glow = NSGradient(colors: [mint.withAlphaComponent(0.16), mint.withAlphaComponent(0)])!
        glow.draw(fromCenter: NSPoint(x: x, y: 230), radius: 0, toCenter: NSPoint(x: x, y: 230), radius: 120, options: [])
    }

    // Decorative coins drifting in the corners
    for (x, y, r, a) in [(38.0, 60.0, 22.0, 0.35), (602.0, 48.0, 14.0, 0.3), (590.0, 380.0, 26.0, 0.25), (54.0, 372.0, 12.0, 0.3)] {
        gold.withAlphaComponent(a).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        NSColor.white.withAlphaComponent(a * 1.4).setStroke()
        let rim = NSBezierPath(ovalIn: NSRect(x: x - r * 0.72, y: y - r * 0.72, width: r * 1.44, height: r * 1.44))
        rim.lineWidth = 1.5
        rim.stroke()
    }

    // Title + subtitle
    func centered(_ text: String, y: Double, font: NSFont, color: NSColor, kern: Double = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: (width - size.width) / 2, y: y))
    }
    let rounded = NSFont.systemFont(ofSize: 30, weight: .bold).fontDescriptor.withDesign(.rounded)!
    centered("WealthCounter", y: 44, font: NSFont(descriptor: rounded, size: 30)!, color: green, kern: 0.3)
    centered("Drag the app into Applications to start earning", y: 86,
             font: .systemFont(ofSize: 14, weight: .medium), color: green.withAlphaComponent(0.6))

    // Curved dashed arrow from the app to Applications
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 246, y: 226))
    arrow.curve(to: NSPoint(x: 384, y: 224), controlPoint1: NSPoint(x: 290, y: 186), controlPoint2: NSPoint(x: 342, y: 186))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 11], count: 2, phase: 0)
    mint.setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    // Wings sit ±35° off the curve's end tangent so the head follows the arc.
    head.move(to: NSPoint(x: 386, y: 212.5))
    head.line(to: NSPoint(x: 390, y: 230))
    head.line(to: NSPoint(x: 372.2, y: 227.8))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // First-launch hint pill
    let hint = NSAttributedString(string: "First launch: right-click the app → Open",
                                  attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                               .foregroundColor: green.withAlphaComponent(0.75)])
    let hs = hint.size()
    let pill = NSRect(x: (width - hs.width) / 2 - 14, y: 360, width: hs.width + 28, height: hs.height + 12)
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    mint.withAlphaComponent(0.35).setStroke()
    let border = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: pill.height / 2, yRadius: pill.height / 2)
    border.lineWidth = 1
    border.stroke()
    hint.draw(at: NSPoint(x: pill.minX + 14, y: pill.minY + 6))
}

func render(scale: Double, to url: URL) throws {
    let px = (Int(width * scale), Int(height * scale))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px.0, pixelsHigh: px.1, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Top-left origin, in points, so layout numbers match Finder's icon coordinates.
    cg.translateBy(x: 0, y: CGFloat(px.1))
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(in: cg)
    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: width, height: height)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try render(scale: 1, to: out.appendingPathComponent("dmg-background.png"))
try render(scale: 2, to: out.appendingPathComponent("dmg-background@2x.png"))
print("Rendered DMG background into \(out.path)")
