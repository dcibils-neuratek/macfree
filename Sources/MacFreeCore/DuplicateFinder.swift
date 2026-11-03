import CryptoKit
import Foundation

public struct DuplicateGroup: Identifiable, Sendable {
    public let id = UUID()
    /// Identical files, with the suggested copy to keep first.
    public let files: [FileNode]

    public init(files: [FileNode]) {
        self.files = files
    }

    public var remaining: [FileNode] { files.filter { $0.parent != nil } }
    public var keeper: FileNode? { remaining.first }
    public var extras: [FileNode] { Array(remaining.dropFirst()) }
    public var wastedSize: Int64 { extras.reduce(0) { $0 + $1.size } }
}

/// Finds files with identical contents. Sizes narrow the field, then hashes prove the match.
public enum DuplicateFinder {
    private static let sampleLength = 64 * 1024
    private static let managedFolderNames: Set<String> = ["build", "dist", "out", "site-packages", "target", "vendor"]

    public static func candidates(in root: FileNode) -> [FileNode] {
        var found: [FileNode] = []
        func walk(_ node: FileNode) {
            for child in node.children {
                if child.name.hasPrefix(".") { continue }
                switch child.kind {
                case .file:
                    if child.size >= LibraryIndex.minimumListedSize { found.append(child) }
                case .directory:
                    // Apps, tools and projects repeat files on purpose, so a copy there isn't spare.
                    if child.name != "Library", !isManaged(child) { walk(child) }
                case .package, .symlink:
                    break
                }
            }
        }
        walk(root)
        return found
    }

    private static func isManaged(_ folder: FileNode) -> Bool {
        LibraryIndex.isJunk(folder) || managedFolderNames.contains(folder.name)
            || folder.children.contains { $0.name == ".git" }
    }

    /// Blocks until done. Returns nil when cancelled.
    public static func find(
        in root: FileNode,
        progress: (_ done: Int, _ total: Int) -> Void = { _, _ in },
        isCancelled: () -> Bool = { false }
    ) -> [DuplicateGroup]? {
        let sameSize = Dictionary(grouping: candidates(in: root), by: \.size).values.filter { $0.count > 1 }
        let total = sameSize.reduce(0) { $0 + $1.count }
        var done = 0
        var groups: [DuplicateGroup] = []

        for bucket in sameSize {
            if isCancelled() { return nil }
            let bySample = Dictionary(grouping: bucket) { digest(of: $0.path, limit: sampleLength) ?? UUID().uuidString }
            for sampled in bySample.values where sampled.count > 1 {
                let byContent = Dictionary(grouping: sampled) { digest(of: $0.path, limit: nil) ?? UUID().uuidString }
                for identical in byContent.values {
                    if isCancelled() { return nil }
                    let copies = withoutClones(identical)
                    if copies.count > 1 { groups.append(DuplicateGroup(files: copies.sorted(by: shouldKeep))) }
                }
            }
            done += bucket.count
            progress(done, total)
        }
        return groups.sorted { $0.wastedSize > $1.wastedSize }
    }

    /// APFS clones share their blocks, so deleting one frees nothing.
    private static func withoutClones(_ files: [FileNode]) -> [FileNode] {
        var seen = Set<Int64>()
        return files.filter { file in
            guard let identifier = try? file.url.resourceValues(forKeys: [.fileContentIdentifierKey]).fileContentIdentifier else {
                return true
            }
            return seen.insert(identifier).inserted
        }
    }

    /// Prefers a settled copy: outside Downloads, then the oldest, then the shortest path.
    static func shouldKeep(_ a: FileNode, _ b: FileNode) -> Bool {
        let aInDownloads = a.path.contains("/Downloads/")
        let bInDownloads = b.path.contains("/Downloads/")
        if aInDownloads != bInDownloads { return bInDownloads }
        if a.created != b.created { return a.created < b.created }
        return a.path.count < b.path.count
    }

    private static func digest(of path: String, limit: Int?) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let more: Bool? = autoreleasepool {
                do {
                    // nil means end of file, while a real read failure throws.
                    guard let chunk = try handle.read(upToCount: min(1 << 20, remaining)), !chunk.isEmpty else { return false }
                    hasher.update(data: chunk)
                    remaining -= chunk.count
                    return true
                } catch {
                    return nil
                }
            }
            guard let more else { return nil }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
