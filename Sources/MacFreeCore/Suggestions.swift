import Foundation

public struct Suggestion: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let items: [FileNode]
    public let reviewSection: LibrarySection

    public var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Groups the scan into the easiest places to start. Nothing is deleted without a review.
public enum Suggestions {
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "iso"]
    public static let staleDownloadAge: TimeInterval = 90 * 24 * 60 * 60
    public static let largeOldFileSize: Int64 = 100_000_000

    public static func build(from index: LibraryIndex, home: String = NSHomeDirectory(), now: Date = Date()) -> [Suggestion] {
        let junk = index.items(in: .junk).filter { !Safety.isProtected($0, home: home) }
        let caches = junk.filter { $0.path.contains("/Library/Caches/") || $0.path.contains("/Library/Logs/") }
        let cacheIDs = Set(caches.map(\.id))
        let builds = junk.filter { !cacheIDs.contains($0.id) }

        let downloads = index.items(in: .downloads).filter { !Safety.isProtected($0, home: home) }
        let installers = downloads.filter {
            FileCategory.fileExtension(of: $0.name).map(installerExtensions.contains) ?? false
        }
        let taken = Set(installers.map(\.id))
        let staleDate = now.addingTimeInterval(-staleDownloadAge)
        let stale = downloads.filter { !taken.contains($0.id) && $0.modified < staleDate }
        let downloadIDs = Set(downloads.map(\.id))
        let oldLarge = index.items(in: .old).filter {
            !downloadIDs.contains($0.id) && $0.size >= largeOldFileSize && !Safety.isProtected($0, home: home)
        }

        let all = [
            Suggestion(id: "caches", title: "App Caches & Logs", detail: "Apps rebuild these when they need them.", symbol: "sparkles", items: caches, reviewSection: .junk),
            Suggestion(id: "installers", title: "Installers in Downloads", detail: "Disk images and installers you've probably already used.", symbol: "shippingbox", items: installers, reviewSection: .downloads),
            Suggestion(id: "builds", title: "Developer Build Folders", detail: "Rebuildable, but projects may need a reinstall or a slow rebuild.", symbol: "hammer", items: builds, reviewSection: .junk),
            Suggestion(id: "stale", title: "Old Downloads", detail: "Files in Downloads not changed in over 90 days.", symbol: "arrow.down.circle", items: stale, reviewSection: .downloads),
            Suggestion(id: "old", title: "Large Old Files", detail: "Over 100 MB and not changed in a year. Check these one by one.", symbol: "clock.arrow.circlepath", items: oldLarge, reviewSection: .old),
        ]
        return all.filter { !$0.items.isEmpty }
    }
}
