#!/usr/bin/swift
// Turns the stills from record-stills.sh into numbered GIF frames, with a cursor clicking through the app.
// Usage: swift scripts/make-tour.swift <stills-folder> <frames-folder>
import AppKit

struct Step {
    let still: String
    let target: CGPoint
    var clicks = 1
    var hold = 1.3
}

// Each step shows a still, moves to a target in window points, and clicking there brings up the next still.
let steps = [
    Step(still: "01-map", target: CGPoint(x: 230, y: 373), hold: 2),
    Step(still: "02-map-selected", target: CGPoint(x: 230, y: 373), clicks: 2),
    Step(still: "03-map-zoomed", target: CGPoint(x: 77, y: 182)),
    Step(still: "04-suggestions", target: CGPoint(x: 1110, y: 153), hold: 2),
    Step(still: "05-suggestions-selected", target: CGPoint(x: 77, y: 210)),
    Step(still: "06-duplicates", target: CGPoint(x: 1070, y: 124), hold: 2),
    Step(still: "07-duplicates-selected", target: CGPoint(x: 77, y: 122)),
    Step(still: "08-largest", target: CGPoint(x: 262, y: 303), hold: 1.6),
    Step(still: "09-largest-checked", target: CGPoint(x: 262, y: 567), hold: 0.5),
    Step(still: "10-largest-selected", target: CGPoint(x: 1128, y: 731), hold: 1),
    Step(still: "11-deleted", target: CGPoint(x: 77, y: 66), hold: 2),
    Step(still: "12-map-after", target: CGPoint(x: 77, y: 66), clicks: 0, hold: 3),
]

let fps = 12.0
let moveTime = 0.7
let size = CGSize(width: 1180, height: 760)
let scale = 2.0

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Usage: make-tour.swift <stills-folder> <frames-folder>") }
let stills = arguments[1]
let output = arguments[2]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func load(_ name: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: "\(stills)/\(name).png")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Missing still: \(name)")
    }
    return image
}

func drawCursor(at point: CGPoint, in context: CGContext) {
    // An arrow in window points, with its tip at the origin.
    let shape: [CGPoint] = [(0, 0), (0, 17), (4, 13), (7, 20), (10, 19), (7, 12.5), (12.5, 12.5)].map { CGPoint(x: $0.0, y: $0.1) }
    let path = CGMutablePath()
    path.addLines(between: shape.map { CGPoint(x: point.x + $0.x, y: point.y + $0.y) })
    path.closeSubpath()
    context.addPath(path)
    context.setFillColor(.black)
    context.setStrokeColor(.white)
    context.setLineWidth(1.5)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)
}

func drawRing(at point: CGPoint, progress: Double, in context: CGContext) {
    let radius = 6 + 16 * progress
    context.setStrokeColor(NSColor.white.withAlphaComponent(1 - progress).cgColor)
    context.setLineWidth(2.5)
    context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}

var frameNumber = 0
func emit(_ still: CGImage, cursor: CGPoint, ring: (point: CGPoint, progress: Double)? = nil) {
    guard let context = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("No drawing context") }
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    context.setFillColor(CGColor(gray: 0.11, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.draw(still, in: CGRect(origin: .zero, size: size))
    // Stills are top-left origin, like the targets, so flip for the overlays.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    if let ring { drawRing(at: ring.point, progress: ring.progress, in: context) }
    drawCursor(at: cursor, in: context)
    frameNumber += 1
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/%04d.png", output, frameNumber)))
}

func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

var cursor = CGPoint(x: 620, y: 300)
for (index, step) in steps.enumerated() {
    let still = load(step.still)
    for _ in 0..<Int(step.hold * fps) { emit(still, cursor: cursor) }

    let start = cursor
    let moveFrames = Int(moveTime * fps)
    for frame in 1...moveFrames where step.target != start {
        let t = ease(Double(frame) / Double(moveFrames))
        cursor = CGPoint(x: start.x + (step.target.x - start.x) * t, y: start.y + (step.target.y - start.y) * t)
        emit(still, cursor: cursor)
    }

    // The next still lands under the ring, so the click looks like what changed the screen.
    let next = index + 1 < steps.count && step.clicks > 0 ? load(steps[index + 1].still) : still
    if step.clicks > 1 {
        for frame in 0..<3 { emit(still, cursor: cursor, ring: (cursor, Double(frame) / 3)) }
    }
    if step.clicks > 0 {
        for frame in 0..<5 { emit(next, cursor: cursor, ring: (cursor, Double(frame) / 5)) }
    }
}
print("Wrote \(frameNumber) frames, \(Int(Double(frameNumber) / fps)) seconds.")
