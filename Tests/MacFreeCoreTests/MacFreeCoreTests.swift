import CoreGraphics
import Foundation
import XCTest
@testable import MacFreeCore

final class MacFreeCoreTests: XCTestCase {
    private var base: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let locked = base.appendingPathComponent("locked").path
        chmod(locked, 0o755)
        try? fm.removeItem(at: base)
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = base.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Random data so APFS can't store it sparsely.
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, bytes) }
        try data.write(to: url)
    }

    private func find(_ name: String, in node: FileNode) -> FileNode? {
        if node.name == name { return node }
        return node.children.lazy.compactMap { self.find(name, in: $0) }.first
    }

    func testFolderSizeIsTheSumOfItsContents() throws {
        try write("a/one.bin", bytes: 2_000_000)
        try write("a/b/two.bin", bytes: 3_000_000)

        let root = try DiskScanner().scan(path: base.path).root
        let a = try XCTUnwrap(find("a", in: root))
        XCTAssertEqual(root.fileCount, 2)
        XCTAssertGreaterThanOrEqual(a.size, 5_000_000)
        XCTAssertLessThan(a.size, 5_200_000)
        XCTAssertEqual(root.path, base.path)
        XCTAssertEqual(find("two.bin", in: root)?.path, base.appendingPathComponent("a/b/two.bin").path)
    }

    func testHardLinksAreOnlyCountedOnce() throws {
        try write("original.bin", bytes: 2_000_000)
        try fm.linkItem(at: base.appendingPathComponent("original.bin"), to: base.appendingPathComponent("link.bin"))

        let root = try DiskScanner().scan(path: base.path).root
        XCTAssertLessThan(root.size, 2_200_000)
    }

    func testSymlinksAreNotFollowed() throws {
        try write("real/big.bin", bytes: 2_000_000)
        try fm.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: base.appendingPathComponent("real"))

        let root = try DiskScanner().scan(path: base.path).root
        XCTAssertEqual(find("link", in: root)?.kind, .symlink)
        XCTAssertLessThan(root.size, 2_200_000)
    }

    func testUnreadableFolderIsReportedAndScanContinues() throws {
        try write("locked/secret.bin", bytes: 1000)
        try write("open/visible.bin", bytes: 1000)
        chmod(base.appendingPathComponent("locked").path, 0)

        let result = try DiskScanner().scan(path: base.path)
        XCTAssertEqual(result.unreadableFolders, 1)
        XCTAssertEqual(result.unreadablePaths, [base.appendingPathComponent("locked").path])
        XCTAssertNotNil(find("visible.bin", in: result.root))
        XCTAssertNotNil(find("locked", in: result.root))
    }

    func testCancelStopsTheScan() throws {
        for i in 0..<3000 { fm.createFile(atPath: base.appendingPathComponent("f\(i)").path, contents: nil) }
        let scanner = DiskScanner()
        scanner.cancel()
        XCTAssertThrowsError(try scanner.scan(path: base.path))
    }

    func testIndexGroupsFilesAndKeepsPackagesWhole() throws {
        try write("movie.mov", bytes: 2_000_000)
        try write("small.mov", bytes: 1000)
        try write("Thing.app/Contents/MacOS/Thing", bytes: 2_000_000)
        try write("Library/cached.mov", bytes: 2_000_000)
        try write("Downloads/setup.dmg", bytes: 2_000_000)
        try write("project/node_modules/lib/photo.png", bytes: 2_000_000)
        try write(".Trash/gone.mov", bytes: 2_000_000)

        let index = LibraryIndex.build(root: try DiskScanner().scan(path: base.path).root)
        XCTAssertEqual(index.items(in: .category(.video)).map(\.name), ["movie.mov"])
        XCTAssertEqual(index.items(in: .category(.application)).map(\.name), ["Thing.app"])
        XCTAssertEqual(index.items(in: .category(.image)), [])
        XCTAssertEqual(index.items(in: .junk).map(\.name), ["node_modules"])
        XCTAssertEqual(index.items(in: .downloads).map(\.name), ["setup.dmg"])
        XCTAssertFalse(index.items(in: .largest).contains { $0.name == "gone.mov" || $0.name == "Thing" })
    }

    func testIndexFindsLibraryCachesAndOldFiles() throws {
        try write("Library/Caches/com.vendor.app/blob", bytes: 2_000_000)
        try write("Library/Caches/com.apple.system/blob", bytes: 2_000_000)
        try write("archive.zip", bytes: 2_000_000)
        try write("recent.zip", bytes: 2_000_000)
        let twoYearsAgo = Date().addingTimeInterval(-2 * LibraryIndex.oldAge)
        try fm.setAttributes([.modificationDate: twoYearsAgo], ofItemAtPath: base.appendingPathComponent("archive.zip").path)

        let index = LibraryIndex.build(root: try DiskScanner().scan(path: base.path).root)
        XCTAssertEqual(index.items(in: .junk).map(\.name), ["com.vendor.app"])
        XCTAssertEqual(index.items(in: .old).map(\.name), ["archive.zip"])
    }

    func testDownloadsListsSmallFilesToo() throws {
        try write("Downloads/note.txt", bytes: 1000)
        try write("Downloads/folder/big.zip", bytes: 2_000_000)
        try write("elsewhere/note.txt", bytes: 1000)

        let index = LibraryIndex.build(root: try DiskScanner().scan(path: base.path).root)
        XCTAssertEqual(Set(index.items(in: .downloads).map(\.name)), ["note.txt", "big.zip"])
        XCTAssertEqual(index.items(in: .largest).map(\.name), ["big.zip"])
    }

    func testSquarifyFillsTheAreaInProportion() {
        let rect = CGRect(x: 10, y: 20, width: 600, height: 400)
        let values = [50.0, 30, 15, 4, 1]
        let rects = Treemap.squarify(values, in: rect)

        XCTAssertEqual(rects.count, values.count)
        for (value, tile) in zip(values, rects) {
            XCTAssertEqual(Double(tile.width * tile.height), value / 100 * 240_000, accuracy: 0.01)
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(tile))
        }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                let overlap = a.insetBy(dx: 0.01, dy: 0.01).intersection(b.insetBy(dx: 0.01, dy: 0.01))
                XCTAssertTrue(overlap.isNull || overlap.isEmpty)
            }
        }
    }

    func testTreemapNestsFoldersAndFoldsTinyFiles() throws {
        try write("big/video.mov", bytes: 5_000_000)
        try write("big/clip.mov", bytes: 3_000_000)
        try write("other.zip", bytes: 2_000_000)
        for i in 0..<20 { try write("big/tiny\(i).txt", bytes: 4096) }
        let root = try DiskScanner().scan(path: base.path).root

        let tiles = Treemap.layout(folder: root, in: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(tiles.first { $0.node?.name == "big" }?.isGroup, true)
        XCTAssertNotNil(tiles.first { $0.node?.name == "video.mov" })
        let folded = try XCTUnwrap(tiles.first { $0.node == nil })
        XCTAssertEqual(folded.hiddenCount, 20)

        let topLevel = tiles.filter { $0.node?.parent === root }.reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(topLevel, root.children.reduce(0) { $0 + $1.size })
    }

    private func writeCopy(of source: String, to target: String) throws {
        let url = base.appendingPathComponent(target)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A plain write, because FileManager.copyItem makes an APFS clone.
        try Data(contentsOf: base.appendingPathComponent(source)).write(to: url)
    }

    func testDuplicatesMatchContentsNotSizeAndKeepTheSettledCopy() throws {
        try write("Documents/report.bin", bytes: 2_000_000)
        try writeCopy(of: "Documents/report.bin", to: "Downloads/report (1).bin")
        try write("same-size-different.bin", bytes: 2_000_000)
        try writeCopy(of: "Documents/report.bin", to: "Library/app/report.bin")
        try write("small.bin", bytes: 1000)
        try writeCopy(of: "small.bin", to: "small copy.bin")

        let root = try DiskScanner().scan(path: base.path).root
        let groups = try XCTUnwrap(DuplicateFinder.find(in: root))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].keeper?.name, "report.bin")
        XCTAssertEqual(groups[0].extras.map(\.name), ["report (1).bin"])
    }

    func testDuplicatesSkipProjectsAndHiddenFolders() throws {
        try write("Movies/film.bin", bytes: 2_000_000)
        try writeCopy(of: "Movies/film.bin", to: "Code/app/.git/objects/film.bin")
        try writeCopy(of: "Movies/film.bin", to: "Code/app/assets/film.bin")
        try writeCopy(of: "Movies/film.bin", to: "work/build/film.bin")
        try writeCopy(of: "Movies/film.bin", to: "work/env/lib/site-packages/film.bin")
        try writeCopy(of: "Movies/film.bin", to: ".tool/film.bin")
        try writeCopy(of: "Movies/film.bin", to: "Backup/film.bin")

        let root = try DiskScanner().scan(path: base.path).root
        let groups = try XCTUnwrap(DuplicateFinder.find(in: root))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map { $0.path.replacingOccurrences(of: base.path + "/", with: "") }), ["Movies/film.bin", "Backup/film.bin"])
    }

    func testClonesAreNotDuplicatesBecauseDeletingThemFreesNothing() throws {
        try write("a.bin", bytes: 2_000_000)
        try fm.copyItem(at: base.appendingPathComponent("a.bin"), to: base.appendingPathComponent("b.bin"))

        let root = try DiskScanner().scan(path: base.path).root
        XCTAssertEqual(DuplicateFinder.find(in: root)?.count, 0)
    }

    func testDuplicateGroupUpdatesAfterACopyIsDeleted() throws {
        try write("a.bin", bytes: 2_000_000)
        try writeCopy(of: "a.bin", to: "b.bin")
        let root = try DiskScanner().scan(path: base.path).root
        let group = try XCTUnwrap(DuplicateFinder.find(in: root)?.first)

        try XCTUnwrap(group.extras.first).detach()
        XCTAssertEqual(group.remaining.count, 1)
        XCTAssertEqual(group.wastedSize, 0)
    }

    private func makeApp(_ name: String, id: String) throws -> String {
        let contents = base.appendingPathComponent("\(name).app/Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": id] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return contents.deletingLastPathComponent().path
    }

    func testLeftoversMatchExactNamesOnly() throws {
        let app = try makeApp("Thing", id: "com.vendor.thing")
        let home = base.path
        try write("Library/Application Support/Thing/data.bin", bytes: 1000)
        try write("Library/Caches/com.vendor.thing/blob", bytes: 1000)
        try write("Library/Preferences/com.vendor.thing.plist", bytes: 100)
        try write("Library/Group Containers/ABC123.com.vendor.thing/data", bytes: 100)
        try write("Library/Application Support/ThingOther/keep.bin", bytes: 1000)
        try write("Library/Caches/com.vendor.thingy/keep", bytes: 1000)

        let leftovers = AppLeftovers.find(appPath: app, home: home)
        XCTAssertGreaterThanOrEqual(leftovers.first { $0.name == "com.vendor.thing" }?.size ?? 0, 1000)
        let found = Set(leftovers.map(\.name))
        XCTAssertEqual(found, ["Thing", "com.vendor.thing", "com.vendor.thing.plist", "ABC123.com.vendor.thing"])
    }

    func testAppleAppsAndVendorFoldersAreNotLeftovers() throws {
        let appleApp = try makeApp("Notes", id: "com.apple.Notes")
        let vendorApp = try makeApp("Google", id: "com.google.thing")
        try write("Library/Application Support/Notes/data", bytes: 100)
        try write("Library/Application Support/Google/Chrome/data", bytes: 100)

        XCTAssertEqual(AppLeftovers.find(appPath: appleApp, home: base.path), [])
        XCTAssertEqual(AppLeftovers.find(appPath: vendorApp, home: base.path), [])
    }

    func testSuggestionsSeparateSafeGroupsWithoutOverlap() throws {
        try write("Library/Caches/com.vendor.app/blob", bytes: 2_000_000)
        try write("project/node_modules/lib.bin", bytes: 2_000_000)
        try write("Downloads/setup.dmg", bytes: 2_000_000)
        try write("Downloads/old-installer.pkg", bytes: 2_000_000)
        try write("Downloads/notes.zip", bytes: 2_000_000)
        try write("Downloads/new.zip", bytes: 2_000_000)
        try write("Movies/old-film.mov", bytes: 2_000_000)
        let longAgo = Date().addingTimeInterval(-2 * LibraryIndex.oldAge)
        for path in ["Downloads/notes.zip", "Downloads/old-installer.pkg"] {
            try fm.setAttributes([.modificationDate: longAgo], ofItemAtPath: base.appendingPathComponent(path).path)
        }

        let root = try DiskScanner().scan(path: base.path).root
        let index = LibraryIndex.build(root: root)
        let groups = Dictionary(uniqueKeysWithValues: Suggestions.build(from: index, home: base.path).map { ($0.id, $0.items.map(\.name)) })
        XCTAssertEqual(groups["caches"], ["com.vendor.app"])
        XCTAssertEqual(groups["builds"], ["node_modules"])
        XCTAssertEqual(Set(groups["installers"] ?? []), ["setup.dmg", "old-installer.pkg"])
        XCTAssertEqual(groups["stale"], ["notes.zip"])
        XCTAssertNil(groups["old"])
    }

    func testFindLocatesNodesByDisplayPath() throws {
        try write("a/b/c.bin", bytes: 1000)
        let root = try DiskScanner().scan(path: base.path).root
        XCTAssertEqual(root.find(displayPath: base.path + "/a/b/c.bin")?.name, "c.bin")
        XCTAssertNil(root.find(displayPath: base.path + "/a/missing"))
        XCTAssertNil(root.find(displayPath: "/elsewhere/c.bin"))
    }

    func testDetachAndAttachKeepTotalsRight() throws {
        try write("a/b/one.bin", bytes: 2_000_000)
        try write("a/two.bin", bytes: 2_000_000)
        let root = try DiskScanner().scan(path: base.path).root
        let before = root.size
        let one = try XCTUnwrap(find("one.bin", in: root))
        let parent = try XCTUnwrap(one.parent)

        XCTAssertTrue(Safety.isProtected(root))
        one.detach()
        XCTAssertFalse(Safety.isProtected(one))
        XCTAssertEqual(root.size, before - one.size)
        XCTAssertEqual(root.fileCount, 1)
        one.attach(to: parent)
        XCTAssertEqual(root.size, before)
        XCTAssertEqual(root.fileCount, 2)
    }

    func testTopLevelDropsNodesInsideSelectedFolders() throws {
        try write("a/one.bin", bytes: 1000)
        try write("two.bin", bytes: 1000)
        let root = try DiskScanner().scan(path: base.path).root
        let a = try XCTUnwrap(find("a", in: root))
        let one = try XCTUnwrap(find("one.bin", in: root))
        let two = try XCTUnwrap(find("two.bin", in: root))

        XCTAssertEqual(Safety.topLevel([one, a, two]).map(\.name), ["a", "two.bin"])
    }

    func testProtectedPaths() {
        let home = "/Users/me"
        let protected = [
            "/", "/System/Library/Kernels", "/usr/bin/ls", "/private/var/vm/sleepimage", "/Applications", "/Users",
            home, "\(home)/Documents", "\(home)/Library", "\(home)/Library/Application Support",
            "\(home)/Library/Keychains/login.keychain-db", "\(home)/.ssh/id_ed25519",
            "/System/Volumes/Data/Users/me/Documents", "/System/Volumes/Data/private/var/db",
        ]
        for path in protected { XCTAssertTrue(Safety.isProtected(path: path, home: home), path) }

        let deletable = [
            "\(home)/Documents/video.mov", "\(home)/Downloads/a.dmg", "\(home)/Library/Caches/com.vendor.app",
            "/Applications/Slack.app", "/usr/local/Cellar/thing", "/System/Volumes/Data/Users/me/Movies/a.mov",
        ]
        for path in deletable { XCTAssertFalse(Safety.isProtected(path: path, home: home), path) }
    }

    func testCloudSyncedPaths() {
        XCTAssertTrue(Safety.isCloudSynced(path: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/a.pdf", home: "/Users/me"))
        XCTAssertFalse(Safety.isCloudSynced(path: "/Users/me/Documents/a.pdf", home: "/Users/me"))
    }

    func testDisplayPathHidesTheDataVolume() {
        XCTAssertEqual(Safety.displayPath("/System/Volumes/Data/Users/me"), "/Users/me")
        XCTAssertEqual(Safety.displayPath("/System/Volumes/Data"), "/")
        XCTAssertEqual(Safety.displayPath("/Users/me"), "/Users/me")
    }
}

extension FileNode: Equatable {
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
}
