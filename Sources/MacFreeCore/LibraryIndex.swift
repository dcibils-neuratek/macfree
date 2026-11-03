import Foundation

public enum LibrarySection: Hashable, Sendable {
    case suggestions
    case duplicates
    case map
    case browse
    case largest
    case category(FileCategory)
    case junk
    case old
    case downloads
}

/// Ready-made lists for the sidebar, computed once from the scanned tree.
public struct LibraryIndex: Sendable {
    /// Smaller files are only reachable through Browse; they would bury everything worth deleting.
    public static let minimumListedSize: Int64 = 1_000_000
    public static let oldAge: TimeInterval = 365 * 24 * 60 * 60

    private static let junkFolderNames: Set<String> = [
        "node_modules", "DerivedData", "__pycache__", "Pods", "iOS DeviceSupport", ".npm", ".pnpm-store", ".cache",
    ]

    public private(set) var lists: [LibrarySection: [FileNode]] = [:]

    public init() {}

    public func items(in section: LibrarySection) -> [FileNode] { lists[section] ?? [] }

    public func total(of section: LibrarySection) -> Int64 {
        items(in: section).reduce(0) { $0 + $1.size }
    }

    public static func build(root: FileNode, now: Date = Date()) -> LibraryIndex {
        var index = LibraryIndex()
        index.walk(root, inLibrary: false, inDownloads: false, inJunk: false, oldBefore: now.addingTimeInterval(-oldAge), isRoot: true)
        return index
    }

    private mutating func add(_ node: FileNode, to section: LibrarySection) {
        lists[section, default: []].append(node)
    }

    private mutating func walk(_ node: FileNode, inLibrary: Bool, inDownloads: Bool, inJunk: Bool, oldBefore: Date, isRoot: Bool = false) {
        if node.name == ".Trash" || node.name == ".Trashes" { return }

        // Runs before the package check: cache folders are often named after a bundle id, like com.vendor.app.
        var nowInJunk = inJunk
        if !inJunk, !isRoot, node.kind == .directory || node.kind == .package, Self.isJunk(node) {
            nowInJunk = true
            if node.size >= Self.minimumListedSize { add(node, to: .junk) }
        }

        if node.kind != .directory {
            let isListed = node.size >= Self.minimumListedSize
            if isListed { add(node, to: .largest) }
            guard !inLibrary, !nowInJunk else { return }
            // Downloads lists everything: people expect to see the whole folder there.
            if inDownloads { add(node, to: .downloads) }
            guard isListed else { return }
            if node.category != .other { add(node, to: .category(node.category)) }
            if node.modified < oldBefore, node.category != .application { add(node, to: .old) }
            return
        }

        let library = inLibrary || node.name == "Library"
        let downloads = inDownloads || node.name == "Downloads" && !inLibrary
        for child in node.children {
            walk(child, inLibrary: library, inDownloads: downloads, inJunk: nowInJunk, oldBefore: oldBefore)
        }
    }

    /// Only folders that tools and apps rebuild on their own.
    static func isJunk(_ node: FileNode) -> Bool {
        if junkFolderNames.contains(node.name) { return true }
        guard let parent = node.parent, parent.name == "Caches" || parent.name == "Logs",
              parent.parent?.name == "Library" else { return false }
        return !node.name.hasPrefix("com.apple.")
    }
}
