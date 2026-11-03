import CoreGraphics
import Foundation

public struct TreemapTile: Sendable {
    public let rect: CGRect
    /// nil for the block that stands in for many small items.
    public let node: FileNode?
    public let size: Int64
    public let hiddenCount: Int
    /// A folder drawn as a frame around its contents.
    public let isGroup: Bool
}

/// Lays a folder out as nested rectangles whose areas match their sizes.
public enum Treemap {
    public static let headerHeight: CGFloat = 18
    private static let minimumTileArea: CGFloat = 90
    private static let maximumTilesPerFolder = 120
    private static let gap: CGFloat = 2

    public static func layout(folder: FileNode, in rect: CGRect, maxDepth: Int = 3) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        add(folder, in: rect, depth: 1, maxDepth: maxDepth, to: &tiles)
        return tiles
    }

    private static func add(_ folder: FileNode, in rect: CGRect, depth: Int, maxDepth: Int, to tiles: inout [TreemapTile]) {
        let items = folder.children.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0, rect.width > 0, rect.height > 0 else { return }

        // Anything too small to see or click folds into one block, so its bytes still take up room.
        let areaPerByte = rect.width * rect.height / CGFloat(total)
        var shown = items.prefix { CGFloat($0.size) * areaPerByte >= minimumTileArea }
        shown = shown.prefix(maximumTilesPerFolder)
        let hidden = items.dropFirst(shown.count)
        let hiddenSize = hidden.reduce(Int64(0)) { $0 + $1.size }

        var values = shown.map { Double($0.size) }
        if hiddenSize > 0 { values.append(Double(hiddenSize)) }
        let rects = squarify(values, in: rect)

        for (item, itemRect) in zip(shown, rects) {
            let inner = itemRect.insetBy(dx: gap / 2, dy: gap / 2)
            let canNest = item.kind == .directory && !item.children.isEmpty && depth < maxDepth
                && inner.width >= 70 && inner.height >= 54
            tiles.append(TreemapTile(rect: inner, node: item, size: item.size, hiddenCount: 0, isGroup: canNest))
            if canNest {
                let contents = CGRect(
                    x: inner.minX + gap, y: inner.minY + headerHeight,
                    width: inner.width - gap * 2, height: inner.height - headerHeight - gap
                )
                add(item, in: contents, depth: depth + 1, maxDepth: maxDepth, to: &tiles)
            }
        }
        if hiddenSize > 0, let last = rects.last {
            tiles.append(TreemapTile(rect: last.insetBy(dx: gap / 2, dy: gap / 2), node: nil, size: hiddenSize, hiddenCount: hidden.count, isGroup: false))
        }
    }

    /// Squarified treemap (Bruls et al.). `values` must be positive and sorted largest first.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        var result: [CGRect] = []
        var remaining = rect
        var index = 0
        while index < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [areas[index]]
            var next = index + 1
            while next < areas.count, worstRatio(row + [areas[next]], side: side) <= worstRatio(row, side: side) {
                row.append(areas[next])
                next += 1
            }

            let thickness = CGFloat(row.reduce(0, +) / side)
            var offset: CGFloat = 0
            let fillsColumn = remaining.width >= remaining.height
            for area in row {
                let length = CGFloat(area) / thickness
                result.append(fillsColumn
                    ? CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length)
                    : CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness))
                offset += length
            }
            if fillsColumn {
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY, width: remaining.width - thickness, height: remaining.height)
            } else {
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness, width: remaining.width, height: remaining.height - thickness)
            }
            index = next
        }
        return result
    }

    private static func worstRatio(_ row: [Double], side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else { return .infinity }
        return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
    }
}
