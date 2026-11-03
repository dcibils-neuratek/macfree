import AppKit
import MacFreeCore
import SwiftUI

/// Colors follow the file type, so a color means the same thing at every zoom level.
private enum MapPalette {
    static let legend: [(String, FileCategory)] = [
        ("Video, Images & Audio", .video), ("Documents & Archives", .document), ("Apps", .application), ("Everything Else", .other),
    ]

    /// Only three hues: a treemap puts every color beside every other, and more can't stay distinct for colorblind viewers.
    static func hex(_ category: FileCategory, dark: Bool) -> UInt32 {
        switch category {
        case .video, .image, .audio: dark ? 0x3987E5 : 0x2A78D6
        case .document, .archive: dark ? 0xD95926 : 0xEB6834
        case .application: dark ? 0x199E70 : 0x1BAF7A
        case .other: dark ? 0x5F5E5A : 0xA3A29C
        }
    }

    static func color(_ value: UInt32) -> Color {
        Color(red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }

    /// Black or white, whichever reads better on this fill.
    static func text(on value: UInt32) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let c = Double(value >> shift & 255) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) ? .black : .white
    }
}

private struct MapKey: Equatable {
    let folder: FileNode.ID?
    let size: CGSize
    let version: Int
}

struct DiskMapView: View {
    private var model: AppModel { .shared }
    @Environment(\.colorScheme) private var colorScheme
    @State private var tiles: [TreemapTile] = []
    @State private var hovered: TreemapTile?
    @State private var pointer: CGPoint = .zero

    var body: some View {
        VStack(spacing: 8) {
            legend
            GeometryReader { proxy in
                map(size: proxy.size)
            }
            MapDetailBar(folder: model.browseFolder)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(MapPalette.legend, id: \.0) { label, category in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MapPalette.color(MapPalette.hex(category, dark: colorScheme == .dark)))
                        .frame(width: 11, height: 11)
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Larger block, more space").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func map(size: CGSize) -> some View {
        Canvas { context, _ in
            for tile in tiles { draw(tile, in: &context) }
        }
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                pointer = location
                hovered = tile(at: location)
            case .ended:
                hovered = nil
            }
        }
        .gesture(
            SpatialTapGesture(count: 2).onEnded { value in
                if let node = tile(at: value.location)?.node { model.open(node) }
            }.exclusively(before: SpatialTapGesture(count: 1).onEnded { value in
                model.mapSelection = tile(at: value.location)?.node
            })
        )
        .contextMenu {
            if let node = hovered?.node { menu(for: node) }
        }
        .overlay(alignment: .topLeading) {
            if let hovered { tooltip(for: hovered, in: size) }
        }
        .task(id: MapKey(folder: model.browseFolder?.id, size: size, version: model.treeVersion)) {
            hovered = nil
            if let folder = model.browseFolder {
                tiles = Treemap.layout(folder: folder, in: CGRect(origin: .zero, size: size))
            }
        }
    }

    @ViewBuilder
    private func menu(for node: FileNode) -> some View {
        if node.canDrillIn {
            Button("Zoom In") { model.open(node) }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Button("Quick Look") { model.quickLookURL = node.url }
        if !Safety.isProtected(node) {
            Divider()
            Button("Check") { model.setChecked(node, true) }
            Button("Delete…", role: .destructive) { model.requestDelete([node]) }
        }
    }

    private func tile(at point: CGPoint) -> TreemapTile? {
        // Children come after their parent, so the last match is the most specific.
        tiles.last { $0.rect.contains(point) }
    }

    private func isSame(_ tile: TreemapTile, _ other: TreemapTile?) -> Bool {
        guard let other else { return false }
        return tile.rect == other.rect
    }

    private func draw(_ tile: TreemapTile, in context: inout GraphicsContext) {
        let dark = colorScheme == .dark
        let shape = Path(roundedRect: tile.rect, cornerRadius: tile.rect.width < 10 || tile.rect.height < 10 ? 1 : 4)

        if tile.isGroup {
            context.fill(shape, with: .color(.primary.opacity(0.07)))
            if let node = tile.node {
                let line = "\(node.name)  \(Format.size(node.size))"
                let label = Self.fit(line, width: tile.rect.width - 10, font: 7)
                let text = context.resolve(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary))
                context.draw(text, at: CGPoint(x: tile.rect.minX + 5, y: tile.rect.minY + Treemap.headerHeight / 2), anchor: .leading)
            }
        } else {
            let category = tile.node?.kind == .directory ? FileCategory.other : tile.node?.category ?? .other
            let fill = MapPalette.hex(category, dark: dark)
            context.fill(shape, with: .color(MapPalette.color(fill)))
            drawLabels(tile, ink: MapPalette.text(on: fill), in: context)
        }

        if isSame(tile, hovered) {
            context.stroke(shape, with: .color(.primary), lineWidth: 1.5)
        }
        if let selected = model.mapSelection, tile.node === selected {
            context.stroke(shape, with: .color(.accentColor), lineWidth: 3)
        }
    }

    private func drawLabels(_ tile: TreemapTile, ink: Color, in context: GraphicsContext) {
        let rect = tile.rect
        guard rect.width >= 46, rect.height >= 18 else { return }
        var name = tile.node?.name ?? "\(tile.hiddenCount.formatted()) smaller items"
        if tile.node == nil, tile.hiddenCount == 1 { name = "1 smaller item" }

        var clipped = context
        clipped.clip(to: Path(rect))
        let origin = CGPoint(x: rect.minX + 6, y: rect.minY + 5)
        let title = Self.fit(name, width: rect.width - 12, font: 6.6)
        clipped.draw(context.resolve(Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(ink)), at: origin, anchor: .topLeading)
        if rect.height >= 36 {
            let size = context.resolve(Text(Format.size(tile.size)).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8)))
            clipped.draw(size, at: CGPoint(x: origin.x, y: origin.y + 14), anchor: .topLeading)
        }
    }

    private static func fit(_ text: String, width: CGFloat, font: CGFloat) -> String {
        let limit = max(Int(width / font), 2)
        return text.count <= limit ? text : text.prefix(limit - 1) + "…"
    }

    private func tooltip(for tile: TreemapTile, in size: CGSize) -> some View {
        let width: CGFloat = 250
        let height: CGFloat = 62
        let x = min(pointer.x + 14, size.width - width - 4)
        let y = min(pointer.y + 14, size.height - height - 4)
        let total = max(model.browseFolder?.size ?? 1, 1)
        return VStack(alignment: .leading, spacing: 2) {
            Text(tile.node?.name ?? "\(tile.hiddenCount.formatted()) smaller items")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(Format.size(tile.size)), \((Double(tile.size) / Double(total)).formatted(.percent.precision(.fractionLength(1)))) of this folder")
                .font(.caption)
                .monospacedDigit()
            Text(tile.node?.kindLabel ?? "Grouped because they're too small to draw")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .offset(x: max(x, 4), y: max(y, 4))
        .allowsHitTesting(false)
    }
}

private struct MapDetailBar: View {
    private var model: AppModel { .shared }
    let folder: FileNode?

    var body: some View {
        HStack(spacing: 10) {
            if let node = model.mapSelection {
                FileIcon(node: node, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text("\(Format.size(node.size))  ·  \(node.displayPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if node.canDrillIn {
                    Button("Zoom In") { model.open(node) }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                if Safety.isProtected(node) {
                    Label("Protected", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(model.isChecked(node) ? "Unselect" : "Select") { model.setChecked(node, !model.isChecked(node)) }
                    Button("Delete…") { model.requestDelete([node]) }
                }
            } else {
                Text("Click a block for details. Double-click a folder to zoom in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let parent = folder?.parent {
                    Button { model.browseFolder = parent } label: { Label("Zoom Out", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
            }
        }
        .frame(height: 34)
    }
}
