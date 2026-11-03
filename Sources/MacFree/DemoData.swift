import Foundation
import MacFreeCore

/// Made-up files for marketing screenshots, so no real home folder ends up on the website.
/// Launch with `--demo`. None of these paths exist, so deleting in this mode does nothing.
enum DemoData {
    private indirect enum Item {
        case file(String, Double, Int = 40)
        case app(String, Double)
        case folder(String, [Item])
    }

    private static let gigabyte = 1_000_000_000.0

    private static let home: [Item] = [
        .folder("Library", [
            .folder("Caches", [
                .folder("com.spotify.client", [.file("data.bin", 3.8)]),
                .folder("com.figma.Desktop", [.file("data.bin", 2.1)]),
                .folder("Homebrew", [.file("downloads.tar", 1.6)]),
            ]),
            .folder("Application Support", [
                .folder("Slack", [.file("store.db", 2.4)]),
                .folder("Steam", [.file("Cyber Racer.pak", 21.5), .file("Island Quest.pak", 11.2)]),
            ]),
            .folder("Developer", [
                .folder("DerivedData", [.file("Index.noindex", 7.4), .file("Build.noindex", 5.2)]),
                .folder("iOS DeviceSupport", [.file("iOS 26.1.dmg", 4.3)]),
            ]),
        ]),
        .folder("Movies", [
            .file("Wedding Film Final.mov", 24.6, 900),
            .file("Drone Footage 4K.mp4", 14.2, 700),
            .file("Conference Talk.mov", 8.1, 500),
            .file("Family Trip.mp4", 5.4, 30),
        ]),
        .folder("Pictures", [
            .file("Portfolio Shoot.psd", 3.2, 800),
            .file("Panorama Raw.dng", 1.4, 600),
            .file("Album Export.heic", 0.9),
            .file("Product Mockups.psd", 2.3, 200),
        ]),
        .folder("Downloads", [
            .file("macOS Installer.dmg", 13.4, 500),
            .file("Ubuntu Desktop.iso", 5.9, 420),
            .file("Design Assets.zip", 3.8, 90),
            .file("Project Backup 2024.zip", 7.2, 640),
            .file("Annual Report.pdf", 0.4, 12),
            .file("Keynote Recording.mp4", 2.7, 150),
            .file("Sample Library.tar.gz", 1.8, 300),
        ]),
        .folder("Documents", [
            .file("Tax Archive.zip", 2.2, 700),
            .file("Client Presentations.pptx", 1.3, 80),
            .file("Research Papers.pdf", 0.8, 400),
            .file("Podcast Master.wav", 3.1, 260),
        ]),
        .folder("Projects", [
            .folder("storefront", [.folder("node_modules", [.file("packages.tar", 3.4)]), .file("video-assets.zip", 2.2, 120)]),
            .folder("mobile-app", [.folder("Pods", [.file("frameworks.tar", 2.6)]), .folder("build", [.file("App.xcarchive.zip", 4.1, 60)])]),
            .folder("ml-experiments", [.file("training-data.tar", 9.8, 500), .file("model-weights.bin", 6.3, 200)]),
        ]),
        .folder("Applications", [
            .app("Xcode.app", 11.8), .app("Final Cut Pro.app", 6.2), .app("Photo Editor.app", 3.4), .app("Music Studio.app", 2.7),
        ]),
    ]

    static func makeRoot(now: Date = Date()) -> FileNode {
        let root = node("/Users/alex", .directory, .other, 0, now, 0)
        for item in home { add(item, to: root, now: now) }
        return root
    }

    private static func add(_ item: Item, to parent: FileNode, now: Date) {
        switch item {
        case .file(let name, let gigabytes, let age):
            node(name, .file, .of(name: name), gigabytes, now, age).attach(to: parent)
        case .app(let name, let gigabytes):
            node(name, .package, .application, gigabytes, now, 90).attach(to: parent)
        case .folder(let name, let items):
            let folder = node(name, .directory, .other, 0, now, 20)
            folder.attach(to: parent)
            for child in items { add(child, to: folder, now: now) }
        }
    }

    private static func node(_ name: String, _ kind: FileNode.Kind, _ category: FileCategory, _ gigabytes: Double, _ now: Date, _ age: Int) -> FileNode {
        let date = now.addingTimeInterval(-Double(age) * 86_400)
        return FileNode(name: name, kind: kind, category: category, size: Int64(gigabytes * gigabyte), modified: date, created: date)
    }
}
