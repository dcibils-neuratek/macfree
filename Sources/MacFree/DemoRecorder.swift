import AppKit
import MacFreeCore
import SwiftUI

/// Walks through the app with sample data and saves Retina stills of each step, for the website.
/// Run with `--demo` and `MACFREE_RECORD=<folder>`. It draws the window itself, so it needs no screen recording access.
@MainActor
enum DemoRecorder {
    static let windowSize = CGSize(width: 1180, height: 760)

    /// Set through the environment, because macOS can take a path argument for a document and show no window.
    static let folder = ProcessInfo.processInfo.environment["MACFREE_RECORD"]

    /// Materials draw clear off-screen, which lets table rows show through, so bars go solid while recording.
    static var barStyle: AnyShapeStyle {
        folder == nil ? AnyShapeStyle(.bar) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }

    static func run(to folder: String, model: AppModel) async {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        guard let window = await mainWindow() else {
            FileHandle.standardError.write(Data("No window appeared, so nothing was recorded.\n".utf8))
            exit(1)
        }
        window.setContentSize(windowSize)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        var step = 0
        func capture(_ name: String) async {
            // An inactive window draws gray, so win focus back if something else took it.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(900))
            step += 1
            save(window, to: "\(folder)/\(String(format: "%02d", step))-\(name).png")
        }

        let root = model.root
        func node(_ path: String) -> FileNode? { root?.find(displayPath: "/Users/alex/" + path) }
        func suggestion(_ id: String) -> [FileNode] { model.suggestions.first { $0.id == id }?.items ?? [] }

        await capture("map")
        model.mapSelection = node("Movies")
        await capture("map-selected")
        model.browseFolder = node("Movies")
        await capture("map-zoomed")

        model.browseFolder = root
        model.section = .suggestions
        await capture("suggestions")
        model.check(suggestion("caches"))
        await capture("suggestions-selected")

        model.section = .duplicates
        model.loadDemoDuplicates()
        await capture("duplicates")
        model.check(model.activeDuplicates.flatMap(\.extras))
        await capture("duplicates-selected")

        model.section = .largest
        await capture("largest")
        model.check([node("Downloads/macOS Installer.dmg")].compactMap(\.self))
        await capture("largest-checked")
        model.check([node("Downloads/Project Backup 2024.zip")].compactMap(\.self))
        await capture("largest-selected")

        model.applyDemoDeletion()
        await capture("deleted")
        model.notice = nil
        model.section = .map
        await capture("map-after")

        NSApp.terminate(nil)
    }

    private static func mainWindow() async -> NSWindow? {
        for _ in 0..<200 {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) { return window }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func save(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview else { return }
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        context.cgContext.scaleBy(x: 2, y: 2)
        view.displayIgnoringOpacity(view.bounds, in: context)
        context.flushGraphics()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
