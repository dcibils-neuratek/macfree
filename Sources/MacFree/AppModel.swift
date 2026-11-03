import AppKit
import MacFreeCore
import Observation

struct DiskUsage {
    var total: Int64
    var available: Int64
    var used: Int64 { total - available }

    static func current() -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskUsage(total: Int64(total), available: available)
    }
}

struct TrashedItem {
    let node: FileNode?
    let parent: FileNode?
    let originalURL: URL
    let trashURL: URL
}

struct Notice {
    var message: String
    var trashed: [TrashedItem] = []
}

@MainActor
@Observable
final class AppModel {
    enum Phase { case welcome, scanning, results }

    static let shared = AppModel()
    nonisolated static let rowLimit = 5000

    var phase: Phase = .welcome
    var progress: ScanProgress?
    var disk = DiskUsage.current()
    var trashSize: Int64?
    private(set) var scanPath: String?

    private(set) var root: FileNode?
    private(set) var index = LibraryIndex()
    var unreadableFolders = 0
    private(set) var unreadablePaths = Set<String>()
    /// Bumped whenever the tree changes, so the disk map redraws.
    private(set) var treeVersion = 0
    var mapSelection: FileNode?

    private(set) var duplicates: [DuplicateGroup] = []
    private(set) var hasSearchedDuplicates = false
    private(set) var duplicateProgress: (done: Int, total: Int)?
    private var duplicateSearch: DuplicateSearch?

    var section: LibrarySection = .map { didSet { tableSelection = []; refreshRows() } }
    var browseFolder: FileNode? { didSet { tableSelection = []; mapSelection = nil; refreshRows() } }
    var search = "" { didSet { refreshRows() } }
    var minimumSize: Int64 = 0 { didSet { refreshRows() } }
    var sortOrder = [KeyPathComparator(\FileNode.size, order: .reverse)] { didSet { refreshRows() } }

    private(set) var rows: [FileNode] = []
    private(set) var matchingCount = 0
    private(set) var largestRowSize: Int64 = 1
    var tableSelection = Set<FileNode.ID>()

    private(set) var checked: [FileNode.ID: FileNode] = [:]
    var pendingDeletion: [FileNode]?
    var isDeleting = false
    var notice: Notice?
    var failureMessage: String?
    var quickLookURL: URL?

    private var scanner: DiskScanner?
    private var refreshTask: Task<Void, Never>?

    private init() {
        refreshTrashSize()
        if let flag = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.indices.contains(flag + 1) {
            startScan(path: CommandLine.arguments[flag + 1])
        } else if CommandLine.arguments.contains("--demo") {
            loadDemo()
        }
    }

    private func loadDemo() {
        let demoRoot = DemoData.makeRoot()
        root = demoRoot
        index = LibraryIndex.build(root: demoRoot)
        scanPath = demoRoot.path
        browseFolder = demoRoot
        disk = DiskUsage(total: 494_000_000_000, available: 46_000_000_000)
        trashSize = nil
        phase = .results
        refreshRows()
    }

    // MARK: Scanning

    func startScan(path: String) {
        let scanner = DiskScanner()
        self.scanner = scanner
        scanPath = path
        progress = nil
        phase = .scanning
        clearResults()

        Task {
            do {
                let result: ScanResult = try await withCheckedThrowingContinuation { continuation in
                    // A dedicated blocking thread: the scan changes that thread's I/O policy while it runs.
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(with: Result {
                            try scanner.scan(path: path) { update in
                                Task { @MainActor [weak self] in
                                    if self?.phase == .scanning { self?.progress = update }
                                }
                            }
                        })
                    }
                }
                let index = await Self.buildIndex(root: result.root)
                guard self.scanner === scanner else { return }
                root = result.root
                self.index = index
                unreadableFolders = result.unreadableFolders
                unreadablePaths = result.unreadablePaths
                browseFolder = result.root
                disk = DiskUsage.current()
                phase = .results
                refreshRows()
            } catch ScanError.cancelled {
                if self.scanner === scanner { phase = .welcome }
            } catch {
                guard self.scanner === scanner else { return }
                phase = .welcome
                failureMessage = "MacFree couldn't open \(path)."
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    func rescan() {
        if let scanPath { startScan(path: scanPath) }
    }

    func reset() {
        scanner?.cancel()
        scanner = nil
        scanPath = nil
        clearResults()
        phase = .welcome
    }

    private func clearResults() {
        root = nil
        index = LibraryIndex()
        browseFolder = nil
        rows = []
        checked = [:]
        notice = nil
        unreadableFolders = 0
        unreadablePaths = []
        mapSelection = nil
        cancelDuplicates()
        duplicates = []
        hasSearchedDuplicates = false
    }

    /// What the current results cover, in the user's words.
    var scopeName: String {
        guard let scanPath else { return "Choose Location" }
        if scanPath == NSHomeDirectory() { return "Home Folder" }
        if scanPath == DiskScanner.dataVolume { return "Entire Disk" }
        return (scanPath as NSString).lastPathComponent
    }

    var coversHome: Bool {
        guard let scanPath else { return false }
        return scanPath == DiskScanner.dataVolume || (NSHomeDirectory() + "/").hasPrefix(scanPath + "/")
    }

    var downloadsBlocked: Bool { unreadablePaths.contains(NSHomeDirectory() + "/Downloads") }

    /// How many items the size filter is currently hiding.
    var hiddenBySizeCount: Int {
        isBrowsing ? 0 : index.items(in: section).filter { $0.size < minimumSize }.count
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose a folder to scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(path: url.path) }
    }

    private nonisolated static func buildIndex(root: FileNode) async -> LibraryIndex {
        await Task.detached(priority: .userInitiated) { LibraryIndex.build(root: root) }.value
    }

    // MARK: Rows

    var isBrowsing: Bool { section == .browse || section == .map }
    var hasCustomPage: Bool { section == .map || section == .suggestions || section == .duplicates }

    func refreshRows() {
        refreshTask?.cancel()
        let source = isBrowsing ? (browseFolder?.children ?? []) : index.items(in: section)
        let browsing = isBrowsing
        let minimum = minimumSize
        let query = search
        let order = sortOrder
        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            var matches = source
            if !browsing { matches = matches.filter { $0.size >= minimum } }
            if !query.isEmpty { matches = matches.filter { $0.name.localizedCaseInsensitiveContains(query) } }
            matches.sort(using: order)
            let count = matches.count
            let visible = Array(matches.prefix(AppModel.rowLimit))
            let largest = max(matches.map(\.size).max() ?? 1, 1)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                rows = visible
                matchingCount = count
                largestRowSize = largest
            }
        }
    }

    func open(_ node: FileNode) {
        if node.canDrillIn {
            if section != .map { section = .browse }
            browseFolder = node
        } else {
            quickLookURL = node.url
        }
    }

    func nodes(for ids: Set<FileNode.ID>) -> [FileNode] {
        rows.filter { ids.contains($0.id) }
    }

    // MARK: Cleanup

    var suggestions: [Suggestion] {
        _ = treeVersion
        return Suggestions.build(from: index)
    }

    var activeDuplicates: [DuplicateGroup] {
        _ = treeVersion
        return duplicates.filter { $0.remaining.count > 1 }
    }

    func findDuplicates() {
        guard let root, duplicateSearch == nil else { return }
        let search = DuplicateSearch()
        duplicateSearch = search
        duplicateProgress = (0, 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let groups = DuplicateFinder.find(in: root, progress: { done, total in
                Task { @MainActor [weak self] in
                    if self?.duplicateSearch === search { self?.duplicateProgress = (done, total) }
                }
            }, isCancelled: { search.isCancelled })
            Task { @MainActor [weak self] in
                guard let self, duplicateSearch === search else { return }
                duplicateSearch = nil
                duplicateProgress = nil
                if let groups {
                    duplicates = groups
                    hasSearchedDuplicates = true
                }
            }
        }
    }

    func cancelDuplicates() {
        duplicateSearch?.cancel()
        duplicateSearch = nil
        duplicateProgress = nil
    }

    /// Duplicate sets that this deletion would remove completely.
    func duplicateSetsLosingEveryCopy(_ items: [FileNode]) -> Int {
        activeDuplicates.filter { group in
            group.remaining.allSatisfy { file in items.contains { $0 === file || file.isDescendant(of: $0) } }
        }.count
    }

    // MARK: Checking

    var checkedItems: [FileNode] { Safety.topLevel(Array(checked.values)) }
    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + $1.size } }

    func isChecked(_ node: FileNode) -> Bool { checked[node.id] != nil }

    func setChecked(_ node: FileNode, _ value: Bool) {
        guard !value || !Safety.isProtected(node) else { return }
        checked[node.id] = value ? node : nil
    }

    func check(_ nodes: [FileNode]) {
        for node in nodes { setChecked(node, true) }
    }

    func clearChecked() { checked = [:] }

    // MARK: Deleting

    func requestDelete(_ nodes: [FileNode]) {
        let safe = Safety.topLevel(nodes.filter { !Safety.isProtected($0) })
        if !safe.isEmpty { pendingDeletion = safe }
    }

    func requestDeleteFromKeyboard() {
        requestDelete(checked.isEmpty ? nodes(for: tableSelection) : checkedItems)
    }

    func delete(_ nodes: [FileNode], leftovers: [Leftover] = [], permanently: Bool) {
        pendingDeletion = nil
        isDeleting = true
        // Paths must be read before any node is detached from the tree.
        var targets = nodes.map { (node: Optional($0), parent: $0.parent, url: $0.url, size: $0.size, name: $0.name) }
        let root = root
        for leftover in leftovers {
            let node = root?.find(displayPath: leftover.path)
            if let node, nodes.contains(where: { $0 === node || node.isDescendant(of: $0) }) { continue }
            targets.append((node, node?.parent, URL(fileURLWithPath: leftover.path), leftover.size, leftover.name))
        }
        let urls = targets.map(\.url)

        Task {
            let outcomes: [(Int, Result<URL?, Error>)] = await Task.detached(priority: .userInitiated) {
                urls.enumerated().map { offset, url in
                    (offset, Result {
                        if permanently {
                            try FileManager.default.removeItem(at: url)
                            return nil
                        }
                        var inTrash: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
                        return inTrash as URL?
                    })
                }
            }.value

            var trashed: [TrashedItem] = []
            var removedBytes: Int64 = 0
            var failures: [String] = []
            for (offset, outcome) in outcomes {
                let target = targets[offset]
                switch outcome {
                case .success(let trashURL):
                    removedBytes += target.size
                    if let node = target.node {
                        node.detach()
                        checked[node.id] = nil
                        if mapSelection === node { mapSelection = nil }
                    }
                    if let trashURL {
                        trashed.append(TrashedItem(node: target.node, parent: target.parent, originalURL: target.url, trashURL: trashURL))
                    }
                case .failure:
                    failures.append(target.name)
                }
            }

            await finishChange()
            isDeleting = false

            let bytes = Format.size(removedBytes)
            if removedBytes > 0 || outcomes.count > failures.count {
                notice = permanently
                    ? Notice(message: "Deleted \(bytes). The space is free now.")
                    : Notice(message: "Moved \(bytes) to the Trash. Empty it to get the space back.", trashed: trashed)
            }
            if !failures.isEmpty {
                let list = failures.prefix(5).joined(separator: ", ")
                let more = failures.count > 5 ? " and \(failures.count - 5) more" : ""
                failureMessage = "Couldn't delete \(list)\(more). macOS may be protecting these items, or they may be in use."
            }
        }
    }

    func undo(_ notice: Notice) {
        var failed = 0
        for item in notice.trashed {
            do {
                try FileManager.default.moveItem(at: item.trashURL, to: item.originalURL)
                if let node = item.node, let parent = item.parent { node.attach(to: parent) }
            } catch {
                failed += 1
            }
        }
        self.notice = nil
        if failed > 0 { failureMessage = "\(failed) item(s) couldn't be restored. They're still in the Trash." }
        Task { await finishChange() }
    }

    private func finishChange() async {
        if let root { index = await Self.buildIndex(root: root) }
        disk = DiskUsage.current()
        treeVersion += 1
        refreshRows()
        refreshTrashSize()
    }

    // MARK: Trash

    private nonisolated static let trashPath = NSHomeDirectory() + "/.Trash"

    func refreshTrashSize() {
        DispatchQueue.global(qos: .utility).async {
            let result = try? DiskScanner().scan(path: Self.trashPath)
            let size = result.flatMap { $0.unreadableFolders == 0 ? $0.root.size : nil }
            Task { @MainActor [weak self] in self?.trashSize = size }
        }
    }

    func emptyTrash() {
        Task {
            let errorMessage: String? = await Task.detached(priority: .userInitiated) {
                var error: NSDictionary?
                NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
                return error?[NSAppleScript.errorMessage] as? String
            }.value
            if let errorMessage {
                failureMessage = "Couldn't empty the Trash: \(errorMessage)"
            } else {
                notice = Notice(message: "Trash emptied.")
            }
            disk = DiskUsage.current()
            refreshTrashSize()
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

private final class DuplicateSearch: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

enum Format {
    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func size(_ value: Int64) -> String { bytes.string(fromByteCount: value) }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .omitted)
    }
}
