import AppKit
import MacFreeCore
import QuickLook
import SwiftUI

struct ResultsView: View {
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 280)
        } detail: {
            if model.section == .map {
                DetailView()
            } else {
                DetailView()
                    .searchable(text: $model.search, placement: .toolbar, prompt: "Search by name")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { ScopeMenu() }
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.isBrowsing {
                    Picker("Minimum size", selection: $model.minimumSize) {
                        Text("Any size").tag(Int64(0))
                        Text("1 MB or larger").tag(Int64(1_000_000))
                        Text("10 MB or larger").tag(Int64(10_000_000))
                        Text("100 MB or larger").tag(Int64(100_000_000))
                        Text("1 GB or larger").tag(Int64(1_000_000_000))
                    }
                    .pickerStyle(.menu)
                }
                Button { model.rescan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                    .help("Scan again")
            }
        }
    }
}

private struct ScopeMenu: View {
    private var model: AppModel { .shared }

    var body: some View {
        Menu {
            Button("Home Folder") { model.startScan(path: NSHomeDirectory()) }
            Button("Entire Disk") { model.startScan(path: DiskScanner.dataVolume) }
            Button("Choose Folder…") { model.chooseFolder() }
        } label: {
            Label("Scanned: \(model.scopeName)", systemImage: "internaldrive")
                .labelStyle(.titleAndIcon)
        }
        .help("Everything in this window comes from this location. Click to scan somewhere else.")
    }
}

private struct SidebarView: View {
    private var model: AppModel { .shared }
    @State private var confirmingEmptyTrash = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            Section {
                row("Disk Map", "square.grid.3x3.square", .map, showSize: false)
                row("Browse Folders", "folder", .browse, showSize: false)
                row("Largest Files", "arrow.up.right.and.arrow.down.left.rectangle", .largest)
            }
            Section("Clean Up") {
                row("Caches & Builds", "sparkles", .junk)
                row("Downloads", "arrow.down.circle", .downloads)
                row("Old Files", "clock.arrow.circlepath", .old)
            }
            Section("By Type") {
                row("Videos", "film", .category(.video))
                row("Images", "photo", .category(.image))
                row("Audio", "music.note", .category(.audio))
                row("Documents", "doc.text", .category(.document))
                row("Archives", "archivebox", .category(.archive))
                row("Applications", "app.dashed", .category(.application))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let disk = model.disk {
                    VStack(alignment: .leading, spacing: 6) {
                        DiskUsageBar(usage: disk, height: 6)
                        Text("\(Format.size(disk.available)) available of \(Format.size(disk.total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Button { confirmingEmptyTrash = true } label: {
                    HStack {
                        Label("Empty Trash", systemImage: "trash")
                        Spacer()
                        if let size = model.trashSize {
                            Text(Format.size(size)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(model.trashSize == 0)
            }
            .padding(14)
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmingEmptyTrash) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash is permanently deleted, including items you put there before using MacFree.")
        }
    }

    private func row(_ title: String, _ symbol: String, _ section: LibrarySection, showSize: Bool = true) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if showSize {
                let total = model.index.total(of: section)
                if total > 0 {
                    Text(Format.size(total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .tag(section)
    }
}

private struct DetailView: View {
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            if model.unreadableFolders > 0 { accessBanner }
            if model.section == .map {
                DiskMapView()
            } else {
                FileTable()
            }
        }
        .overlay {
            if model.rows.isEmpty, model.section != .map { emptyState }
        }
        .overlay {
            if model.isDeleting {
                ProgressView("Deleting…")
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let notice = model.notice { NoticeBar(notice: notice) }
                if !model.checked.isEmpty { SelectionBar() }
            }
            .animation(.smooth(duration: 0.2), value: model.checked.isEmpty)
            .animation(.smooth(duration: 0.2), value: model.notice?.message)
        }
        .quickLookPreview($model.quickLookURL)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isBrowsing {
                Breadcrumb()
            } else {
                Text(title).font(.title2.weight(.semibold))
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch model.section {
        case .map: "Disk Map"
        case .browse: "Browse Folders"
        case .largest: "Largest Files"
        case .junk: "Caches & Builds"
        case .downloads: "Downloads"
        case .old: "Old Files"
        case .category(let category):
            switch category {
            case .video: "Videos"
            case .image: "Images"
            case .audio: "Audio"
            case .document: "Documents"
            case .archive: "Archives"
            case .application: "Applications"
            case .other: "Other Files"
            }
        }
    }

    private var subtitle: String {
        if model.isBrowsing, let folder = model.browseFolder {
            return "\(Format.size(folder.size)) in \(folder.fileCount.formatted()) files"
        }
        let count = model.matchingCount
        var text = "\(count.formatted()) \(count == 1 ? "item" : "items")"
        if count > AppModel.rowLimit { text += ", showing \(AppModel.rowLimit.formatted())" }
        if model.section == .junk { text += ". Apps and tools rebuild these when needed, but a project may need a reinstall." }
        return text
    }

    private var accessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("\(model.unreadableFolders.formatted()) folders couldn't be read, so totals may be low.")
                .font(.callout)
            Spacer()
            Button("Grant Full Disk Access") { model.openFullDiskAccessSettings() }
                .controlSize(.small)
            Button { model.unreadableFolders = 0 } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var emptyState: some View {
        Group {
            if !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else if model.section == .downloads, model.downloadsBlocked {
                ContentUnavailableView {
                    Label("macOS blocked your Downloads folder", systemImage: "lock.shield")
                } description: {
                    Text("Give MacFree Full Disk Access, then scan again.")
                } actions: {
                    Button("Grant Full Disk Access") { model.openFullDiskAccessSettings() }
                    Button("Scan Again") { model.rescan() }
                }
            } else if model.hiddenBySizeCount > 0 {
                ContentUnavailableView {
                    Label("Everything here is smaller than your filter", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Show All Sizes") { model.minimumSize = 0 }
                }
            } else if !model.coversHome {
                ContentUnavailableView {
                    Label("This scan only covers \(model.scopeName)", systemImage: "scope")
                } description: {
                    Text("Scan your home folder to find your downloads, documents and media.")
                } actions: {
                    Button("Scan Home Folder") { model.startScan(path: NSHomeDirectory()) }
                }
            } else {
                ContentUnavailableView("Nothing here", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct Breadcrumb: View {
    private var model: AppModel { .shared }

    private var trail: [FileNode] {
        var nodes: [FileNode] = []
        var current = model.browseFolder
        while let node = current {
            nodes.insert(node, at: 0)
            current = node.parent
        }
        return nodes
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(trail.enumerated()), id: \.element.id) { offset, node in
                if offset > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Button(label(for: node, at: offset)) { model.browseFolder = node }
                    .buttonStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(node === trail.last ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private func label(for node: FileNode, at offset: Int) -> String {
        guard offset == 0 else { return node.name }
        let path = node.displayPath
        return path == "/" ? "Disk" : (path as NSString).lastPathComponent
    }
}

private struct FileTable: View {
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var model = model
        Table(model.rows, selection: $model.tableSelection, sortOrder: $model.sortOrder) {
            TableColumn("") { node in
                CheckCell(node: node)
            }
            .width(26)

            TableColumn("Name", value: \.name) { node in
                HStack(spacing: 10) {
                    FileIcon(node: node, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                        if !model.isBrowsing {
                            Text(parentPath(of: node))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .width(min: 240, ideal: 380)

            TableColumn("Size", value: \.size) { node in
                HStack(spacing: 10) {
                    Text(Format.size(node.size))
                        .monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                    SizeBar(fraction: Double(node.size) / Double(model.largestRowSize))
                }
            }
            .width(min: 140, ideal: 180)

            TableColumn("Modified", value: \.modified) { node in
                Text(Format.date(node.modified)).foregroundStyle(.secondary)
            }
            .width(min: 84, ideal: 100)

            TableColumn("Created", value: \.created) { node in
                Text(Format.date(node.created)).foregroundStyle(.secondary)
            }
            .width(min: 84, ideal: 100)

            TableColumn("Kind", value: \.kindLabel) { node in
                Text(node.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 84)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            menu(for: model.nodes(for: ids))
        } primaryAction: { ids in
            if let node = model.nodes(for: ids).first { model.open(node) }
        }
        .onKeyPress(.space) {
            guard let node = model.nodes(for: model.tableSelection).first else { return .ignored }
            model.quickLookURL = node.url
            return .handled
        }
    }

    private func parentPath(of node: FileNode) -> String {
        let path = (node.displayPath as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    @ViewBuilder
    private func menu(for nodes: [FileNode]) -> some View {
        if let first = nodes.first {
            let deletable = nodes.filter { !Safety.isProtected($0) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(nodes.map(\.url))
            }
            if first.canDrillIn, nodes.count == 1 {
                Button("Open Folder") { model.open(first) }
            }
            Button("Quick Look") { model.quickLookURL = first.url }
            Divider()
            Button("Check") { model.check(deletable) }
                .disabled(deletable.isEmpty)
            Button("Delete…", role: .destructive) { model.requestDelete(deletable) }
                .disabled(deletable.isEmpty)
        }
    }
}

private struct CheckCell: View {
    private var model: AppModel { .shared }
    let node: FileNode

    var body: some View {
        if Safety.isProtected(node) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("macOS or your account needs this, so MacFree won't delete it")
                .frame(maxWidth: .infinity)
        } else {
            Toggle("Select \(node.name)", isOn: Binding(
                get: { model.isChecked(node) },
                set: { model.setChecked(node, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
        }
    }
}

struct FileIcon: View {
    let node: FileNode
    let size: CGFloat

    var body: some View {
        if node.category == .application, node.kind == .package {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.14), in: .rect(cornerRadius: size * 0.26))
        }
    }

    private var symbol: String {
        if node.kind == .directory { return "folder.fill" }
        if node.kind == .symlink { return "arrow.turn.up.right" }
        switch node.category {
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .image: return "photo.fill"
        case .document: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .application: return "app.fill"
        case .other: return node.kind == .package ? "shippingbox.fill" : "doc.fill"
        }
    }

    private var color: Color {
        if node.kind == .directory { return .blue }
        switch node.category {
        case .video: return .purple
        case .audio: return .pink
        case .image: return .green
        case .document: return .orange
        case .archive: return .brown
        case .application: return .indigo
        case .other: return .gray
        }
    }
}

private struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: max(3, proxy.size.width * min(fraction, 1)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 5)
    }
}

private struct SelectionBar: View {
    private var model: AppModel { .shared }

    var body: some View {
        let items = model.checkedItems
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.size(model.checkedSize))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("\(items.count) \(items.count == 1 ? "item" : "items") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { model.clearChecked() }
                .controlSize(.large)
            Button { model.requestDelete(items) } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct NoticeBar: View {
    private var model: AppModel { .shared }
    let notice: Notice
    @State private var confirmingEmptyTrash = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(notice.message).font(.callout)
            Spacer()
            if !notice.trashed.isEmpty {
                Button("Undo") { model.undo(notice) }
                Button("Empty Trash") { confirmingEmptyTrash = true }
            }
            Button { model.notice = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .confirmationDialog("Empty the Trash?", isPresented: $confirmingEmptyTrash) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash is permanently deleted, including items you put there before using MacFree.")
        }
    }
}
