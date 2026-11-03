import AppKit
import MacFreeCore
import SwiftUI

struct RootView: View {
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .welcome: WelcomeView()
            case .scanning: ScanningView()
            case .results: ResultsView()
            }
        }
        .alert("Something went wrong", isPresented: failureShown) {
            Button("OK") {}
        } message: {
            Text(model.failureMessage ?? "")
        }
        .sheet(item: pendingDeletion) { batch in
            DeleteConfirmationView(items: batch.items)
        }
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { model.failureMessage != nil }, set: { if !$0 { model.failureMessage = nil } })
    }

    private var pendingDeletion: Binding<DeletionBatch?> {
        Binding(
            get: { model.pendingDeletion.map(DeletionBatch.init) },
            set: { model.pendingDeletion = $0?.items }
        )
    }
}

private struct DeletionBatch: Identifiable {
    let items: [FileNode]
    var id: [FileNode.ID] { items.map(\.id) }
}

struct DiskUsageBar: View {
    let usage: DiskUsage
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(usedFraction > 0.9 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.accentColor))
                    .frame(width: max(height, proxy.size.width * usedFraction))
            }
        }
        .frame(height: height)
    }

    private var usedFraction: Double {
        usage.total > 0 ? Double(usage.used) / Double(usage.total) : 0
    }
}

private struct WelcomeView: View {
    private var model: AppModel { .shared }

    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                Text("Free up your Mac")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("See what's taking up space and clear it in a few clicks.")
                    .foregroundStyle(.secondary)
            }

            if let disk = model.disk {
                VStack(spacing: 8) {
                    DiskUsageBar(usage: disk, height: 10)
                    HStack {
                        Text("\(Format.size(disk.used)) used")
                        Spacer()
                        Text("\(Format.size(disk.available)) available")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .frame(width: 520)
            }

            HStack(spacing: 14) {
                ScopeButton(title: "Home Folder", subtitle: "Your files", symbol: "house.fill") {
                    model.startScan(path: NSHomeDirectory())
                }
                ScopeButton(title: "Entire Disk", subtitle: "Everything you can delete", symbol: "internaldrive.fill") {
                    model.startScan(path: DiskScanner.dataVolume)
                }
                ScopeButton(title: "Choose Folder", subtitle: "Pick one location", symbol: "folder.fill") {
                    model.chooseFolder()
                }
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScopeButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(height: 34)
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 164, height: 112)
            .background(isHovering ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct ScanningView: View {
    private var model: AppModel { .shared }

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(Format.size(model.progress?.bytes ?? 0))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: model.progress?.bytes)
            Text("\((model.progress?.files ?? 0).formatted()) files found")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(model.progress?.currentPath ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)
            Button("Cancel") { model.cancelScan() }
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeleteConfirmationView: View {
    private var model: AppModel { .shared }
    let items: [FileNode]
    private let visibleLimit = 6

    @State private var leftovers: [Leftover] = []
    @State private var includeLeftovers = true

    private var selectedLeftovers: [Leftover] { includeLeftovers ? leftovers : [] }
    private var apps: [FileNode] { items.filter { $0.kind == .package && $0.category == .application } }
    private var total: Int64 { items.reduce(0) { $0 + $1.size } + selectedLeftovers.reduce(0) { $0 + $1.size } }
    private var lostDuplicateSets: Int { model.duplicateSetsLosingEveryCopy(items) }
    private var runningApps: [String] {
        apps.filter { app in
            guard let id = AppLeftovers.bundleIdentifier(ofApp: app.path) else { return false }
            return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
        }.map(\.name)
    }
    private var hasCloudItems: Bool { items.contains { Safety.isCloudSynced(path: $0.path) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(items.count == 1 ? "Delete \(items[0].name)?" : "Delete \(items.count) items?")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text("This clears \(Format.size(total)).")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(items.prefix(visibleLimit)) { item in
                    HStack(spacing: 8) {
                        FileIcon(node: item, size: 20)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.size(item.size)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if items.count > visibleLimit {
                    Text("and \(items.count - visibleLimit) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))

            if !leftovers.isEmpty {
                Toggle(isOn: $includeLeftovers) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Also remove \(leftovers.count) related \(leftovers.count == 1 ? "item" : "items") (\(Format.size(leftovers.reduce(0) { $0 + $1.size })))")
                        Text("Settings, caches and app data in your Library. Reinstalling starts fresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            if !runningApps.isEmpty {
                Label("Quit \(runningApps.joined(separator: ", ")) before deleting.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if lostDuplicateSets > 0 {
                Label("This deletes every copy of \(lostDuplicateSets) duplicated \(lostDuplicateSets == 1 ? "file" : "files"), so none will remain.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if hasCloudItems {
                Label("Some items sync with iCloud or another service. Deleting them removes them from your other devices too.", systemImage: "exclamationmark.icloud.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Text("The Trash keeps files recoverable, but the space only comes back once it's emptied.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Delete Permanently", role: .destructive) { model.delete(items, leftovers: selectedLeftovers, permanently: true) }
                Spacer()
                Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") { model.delete(items, leftovers: selectedLeftovers, permanently: false) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 480)
        .task {
            let paths = apps.map(\.path)
            guard !paths.isEmpty else { return }
            leftovers = await Task.detached(priority: .userInitiated) {
                paths.flatMap { AppLeftovers.find(appPath: $0) }
            }.value
        }
    }
}
