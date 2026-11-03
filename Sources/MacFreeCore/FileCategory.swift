import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case video, audio, image, document, archive, application, other

    public var label: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        case .document: "Document"
        case .archive: "Archive"
        case .application: "Application"
        case .other: "File"
        }
    }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        let groups: [(FileCategory, String)] = [
            (.video, "mp4 m4v mov avi mkv webm wmv flv mpg mpeg 3gp mts m2ts prores braw r3d"),
            (.audio, "mp3 m4a aac wav aiff aif flac ogg opus wma caf m4b"),
            (.image, "jpg jpeg png gif heic heif tiff tif bmp webp raw cr2 cr3 nef arw dng psd ai svg"),
            (.document, "pdf doc docx xls xlsx ppt pptx txt rtf md csv pages numbers key epub mobi odt ods odp"),
            (.archive, "zip dmg iso pkg tar gz tgz bz2 xz 7z rar sparseimage sparsebundle img xip"),
        ]
        for (category, extensions) in groups {
            for ext in extensions.split(separator: " ") { map[String(ext)] = category }
        }
        map["app"] = .application
        map["photoslibrary"] = .image
        map["imovielibrary"] = .video
        map["fcpbundle"] = .video
        return map
    }()

    private static let packageExtensions: Set<String> = [
        "app", "appex", "band", "bundle", "dsym", "fcpbundle", "framework", "imovielibrary", "kext", "key",
        "logicx", "musiclibrary", "numbers", "pages", "photoslibrary", "pkg", "playground", "plugin", "rtfd",
        "sparsebundle", "tvlibrary", "xcarchive",
    ]

    static func fileExtension(of name: String) -> String? {
        guard let dot = name.utf8.lastIndex(of: UInt8(ascii: ".")), dot != name.startIndex else { return nil }
        return name[name.index(after: dot)...].lowercased()
    }

    public static func of(name: String) -> FileCategory {
        guard let ext = fileExtension(of: name) else { return .other }
        return byExtension[ext] ?? .other
    }

    public static func isPackage(name: String) -> Bool {
        guard let ext = fileExtension(of: name) else { return false }
        return packageExtensions.contains(ext)
    }
}
