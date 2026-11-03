import Foundation

public struct Leftover: Identifiable, Hashable, Sendable {
    public let path: String
    public let size: Int64
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Finds what an app leaves in ~/Library. Names must match exactly, so a vendor's other apps are untouched.
public enum AppLeftovers {
    // Vendor folders hold data for several apps, so they never count as one app's leftovers.
    private static let sharedFolderNames: Set<String> = ["Adobe", "Apple", "Google", "Microsoft", "Mozilla", "JetBrains"]

    public static func bundleIdentifier(ofApp appPath: String) -> String? {
        let plist = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist")
        return plist?["CFBundleIdentifier"] as? String
    }

    public static func find(appPath: String, home: String = NSHomeDirectory()) -> [Leftover] {
        guard let identifier = bundleIdentifier(ofApp: appPath), !identifier.hasPrefix("com.apple.") else { return [] }
        let library = home + "/Library"
        var paths = [
            "Application Support/\(identifier)", "Caches/\(identifier)", "Containers/\(identifier)",
            "HTTPStorages/\(identifier)", "HTTPStorages/\(identifier).binarycookies", "WebKit/\(identifier)",
            "Logs/\(identifier)", "Preferences/\(identifier).plist", "LaunchAgents/\(identifier).plist",
            "Saved Application State/\(identifier).savedState", "Cookies/\(identifier).binarycookies",
        ].map { "\(library)/\($0)" }

        let appName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        if !sharedFolderNames.contains(appName) {
            paths += ["Application Support", "Caches", "Logs"].map { "\(library)/\($0)/\(appName)" }
        }

        let groups = library + "/Group Containers"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: groups)) ?? []
        where name == identifier || name.hasSuffix("." + identifier) {
            paths.append("\(groups)/\(name)")
        }

        return paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path), !Safety.isProtected(path: path, home: home) else { return nil }
            let size = (try? DiskScanner().scan(path: path).root.size) ?? 0
            return Leftover(path: path, size: size)
        }
    }
}
