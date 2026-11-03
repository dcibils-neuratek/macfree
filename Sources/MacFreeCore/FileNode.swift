import Foundation

/// One entry on disk. The tree is built on a background thread, then only mutated on the main actor.
public final class FileNode: Identifiable, @unchecked Sendable {
    public enum Kind: Sendable { case file, directory, package, symlink }

    public let name: String
    public let kind: Kind
    public let category: FileCategory
    public let modified: Date
    public let created: Date
    public internal(set) var isScanRoot = false
    public internal(set) weak var parent: FileNode?
    public internal(set) var children: [FileNode] = []
    /// Bytes actually allocated on disk, including descendants.
    public internal(set) var size: Int64
    public internal(set) var fileCount: Int

    public init(name: String, kind: Kind, category: FileCategory, size: Int64, modified: Date, created: Date) {
        self.name = name
        self.kind = kind
        self.category = category
        self.size = size
        self.fileCount = kind == .directory || kind == .package ? 0 : 1
        self.modified = modified
        self.created = created
    }

    public var isFolder: Bool { kind == .directory }

    /// Packages like .app look like files to the user, so they are deleted as a unit.
    public var canDrillIn: Bool { kind == .directory && !children.isEmpty }

    /// The real path, usable for file operations.
    public var path: String {
        var parts: [String] = []
        var node: FileNode? = self
        while let current = node {
            parts.append(current.name)
            node = current.parent
        }
        let joined = parts.reversed().joined(separator: "/")
        return joined.hasPrefix("//") ? String(joined.dropFirst()) : joined
    }

    /// The path as the user knows it, without the APFS data volume prefix.
    public var displayPath: String { Safety.displayPath(path) }

    public var url: URL { URL(fileURLWithPath: path) }

    public var kindLabel: String {
        switch kind {
        case .directory: "Folder"
        case .symlink: "Alias"
        case .package: category == .application ? "Application" : "Package"
        case .file: category.label
        }
    }

    /// Removes this node from its parent, updating every ancestor's totals.
    public func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var ancestor: FileNode? = parent
        while let current = ancestor {
            current.size -= size
            current.fileCount -= fileCount
            ancestor = current.parent
        }
        self.parent = nil
    }

    /// Puts a detached node back, undoing `detach()`.
    public func attach(to newParent: FileNode) {
        parent = newParent
        newParent.children.append(self)
        var ancestor: FileNode? = newParent
        while let current = ancestor {
            current.size += size
            current.fileCount += fileCount
            ancestor = current.parent
        }
    }

    public func isDescendant(of other: FileNode) -> Bool {
        var ancestor = parent
        while let current = ancestor {
            if current === other { return true }
            ancestor = current.parent
        }
        return false
    }
}
