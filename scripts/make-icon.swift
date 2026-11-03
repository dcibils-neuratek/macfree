// Draws the app icon. Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = CGFloat(pixels) / 1024

    // macOS icons sit on an 824pt rounded square centered on a 1024pt canvas.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 186 * unit, yRadius: 186 * unit)
    NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.56, blue: 1.0, alpha: 1),
        ending: NSColor(calibratedRed: 0.13, green: 0.82, blue: 0.72, alpha: 1)
    )!.draw(in: shape, angle: -60)

    // A gauge ring, mostly empty: a disk with room to spare.
    let center = NSPoint(x: 512 * unit, y: 512 * unit)
    let radius = 250 * unit
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = 78 * unit
    NSColor.white.withAlphaComponent(0.28).setStroke()
    track.stroke()

    let fill = NSBezierPath()
    fill.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -30, clockwise: true)
    fill.lineWidth = 78 * unit
    fill.lineCapStyle = .round
    NSColor.white.setStroke()
    fill.stroke()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: "\(output)/icon_\(points)x\(points)\(suffix).png")
        try draw(pixels: points * scale).write(to: url)
    }
}
