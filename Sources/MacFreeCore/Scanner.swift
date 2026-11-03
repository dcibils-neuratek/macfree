import Darwin
import Foundation

public struct ScanProgress: Sendable {
    public let files: Int
    public let bytes: Int64
    public let currentPath: String
}

public struct ScanResult: Sendable {
    public let root: FileNode
    /// Folders the OS refused to open, usually because Full Disk Access is missing.
    public let unreadableFolders: Int
    /// The first few hundred of those folders, as the user knows their paths.
    public let unreadablePaths: Set<String>
}

public enum ScanError: Error {
    case cancelled
    case cannotOpen(String)
}

/// Walks a volume with fts, which is far faster than FileManager on millions of files.
public final class DiskScanner: @unchecked Sendable {
    /// The writable half of the boot disk. "/" itself is a read-only system volume.
    public static let dataVolume = "/System/Volumes/Data"

    private let lock = NSLock()
    private var isCancelled = false

    public init() {}

    public func cancel() {
        lock.withLock { isCancelled = true }
    }

    private var cancelled: Bool { lock.withLock { isCancelled } }

    /// Blocks the calling thread until the walk ends. Stays on one volume and never follows symlinks.
    public func scan(path: String, progress: (ScanProgress) -> Void = { _ in }) throws -> ScanResult {
        // Listing an iCloud or Dropbox folder must not download what has been evicted from disk.
        let previousPolicy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer {
            if previousPolicy >= 0 {
                setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previousPolicy)
            }
        }

        var arguments: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { free(arguments[0]) }
        guard let stream = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_COMFOLLOW, nil) else {
            throw ScanError.cannotOpen(path)
        }
        defer { fts_close(stream) }

        var root: FileNode?
        var stack: [FileNode] = []
        var seenHardLinks = Set<UInt64>()
        var unreadable = 0
        var unreadablePaths = Set<String>()
        var files = 0
        var bytes: Int64 = 0
        var nextReport = Date.distantPast
        var sinceCheck = 0

        func add(_ node: FileNode) {
            if let parent = stack.last {
                node.parent = parent
                parent.children.append(node)
            } else if root == nil {
                node.isScanRoot = true
                root = node
            }
        }

        func closeFolder() {
            let folder = stack.removeLast()
            if let parent = stack.last {
                parent.size += folder.size
                parent.fileCount += folder.fileCount
            }
        }

        while let entry = fts_read(stream) {
            sinceCheck += 1
            if sinceCheck >= 2048 {
                sinceCheck = 0
                if cancelled { throw ScanError.cancelled }
                let now = Date()
                if now >= nextReport {
                    nextReport = now.addingTimeInterval(0.08)
                    progress(ScanProgress(files: files, bytes: bytes, currentPath: Safety.displayPath(String(cString: entry.pointee.fts_path))))
                }
            }

            let level = Int(entry.pointee.fts_level)
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                let info = entry.pointee.fts_statp.pointee
                let name = Self.name(of: entry, isRoot: level == 0, rootPath: path)
                let isPackage = FileCategory.isPackage(name: name)
                let node = FileNode(
                    name: name,
                    kind: isPackage ? .package : .directory,
                    category: isPackage ? .of(name: name) : .other,
                    size: Int64(info.st_blocks) * 512,
                    modified: Self.date(info.st_mtimespec),
                    created: Self.date(info.st_birthtimespec)
                )
                add(node)
                stack.append(node)

            case FTS_DP:
                if stack.count == level + 1 { closeFolder() }

            case FTS_DNR, FTS_ERR:
                unreadable += 1
                if unreadablePaths.count < 500 {
                    unreadablePaths.insert(Safety.displayPath(String(cString: entry.pointee.fts_path)))
                }
                if stack.count == level + 1 { closeFolder() }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                let info = entry.pointee.fts_statp.pointee
                var size = Int64(info.st_blocks) * 512
                // Every hard link points at the same blocks, so only the first one counts.
                if info.st_nlink > 1, !seenHardLinks.insert(UInt64(info.st_ino)).inserted { size = 0 }
                let name = Self.name(of: entry, isRoot: level == 0, rootPath: path)
                let isLink = info.st_mode & S_IFMT == S_IFLNK
                let node = FileNode(
                    name: name,
                    kind: isLink ? .symlink : .file,
                    category: isLink ? .other : .of(name: name),
                    size: size,
                    modified: Self.date(info.st_mtimespec),
                    created: Self.date(info.st_birthtimespec)
                )
                add(node)
                if let parent = stack.last {
                    parent.size += size
                    parent.fileCount += 1
                }
                files += 1
                bytes += size

            case FTS_NS:
                unreadable += 1

            default:
                break
            }
        }

        guard let root else { throw ScanError.cannotOpen(path) }
        return ScanResult(root: root, unreadableFolders: unreadable, unreadablePaths: unreadablePaths)
    }

    private static func name(of entry: UnsafeMutablePointer<FTSENT>, isRoot: Bool, rootPath: String) -> String {
        if isRoot { return rootPath.count > 1 && rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath }
        let pathLength = Int(entry.pointee.fts_pathlen)
        let nameLength = Int(entry.pointee.fts_namelen)
        let start = UnsafeRawPointer(entry.pointee.fts_path + (pathLength - nameLength)).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: start, count: nameLength), as: UTF8.self)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
