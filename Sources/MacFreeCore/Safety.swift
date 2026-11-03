import Foundation

/// Decides what the app must never offer to delete.
public enum Safety {
    private static let protectedTrees = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/dev", "/etc", "/var", "/tmp", "/cores", "/Library/Apple",
    ]
    private static let protectedExact: Set<String> = [
        "/", "/Users", "/Applications", "/Library", "/Volumes", "/opt", "/home", "/usr/local",
    ]
    private static let homeFolders = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications"]
    private static let homeTrees = ["Library/Keychains", ".ssh", ".gnupg"]
    private static let userCloudPaths = ["/Library/Mobile Documents", "/Library/CloudStorage"]

    public static func displayPath(_ path: String) -> String {
        let prefix = DiskScanner.dataVolume
        guard path.hasPrefix(prefix) else { return path }
        let rest = String(path.dropFirst(prefix.count))
        return rest.isEmpty ? "/" : rest
    }

    public static func isProtected(path rawPath: String, home: String = NSHomeDirectory()) -> Bool {
        let path = displayPath(rawPath)
        if path == home { return true }
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count + 1))
            if homeFolders.contains(relative) { return true }
            if homeTrees.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { return true }
            // ~/Library/Caches and friends hold the content; the folders themselves must stay.
            let parts = relative.split(separator: "/")
            return parts.count == 2 && parts[0] == "Library"
        }

        // /usr/local is the one writable part of /usr, used by Homebrew on Intel Macs.
        if path.hasPrefix("/usr/local/") { return false }
        if protectedExact.contains(path) { return true }
        return protectedTrees.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    public static func isProtected(_ node: FileNode, home: String = NSHomeDirectory()) -> Bool {
        node.isScanRoot || isProtected(path: node.path, home: home) || node.path == Bundle.main.bundlePath
    }

    /// Files synced to iCloud or another provider vanish from every device when deleted.
    public static func isCloudSynced(path rawPath: String, home: String = NSHomeDirectory()) -> Bool {
        let path = displayPath(rawPath)
        return userCloudPaths.contains { path.hasPrefix(home + $0 + "/") }
    }

    /// Drops anything already covered by a selected parent, so nothing is counted or deleted twice.
    public static func topLevel(_ nodes: [FileNode]) -> [FileNode] {
        let selected = Set(nodes.map(\.id))
        return nodes.filter { node in
            var ancestor = node.parent
            while let current = ancestor {
                if selected.contains(current.id) { return false }
                ancestor = current.parent
            }
            return true
        }
    }
}
