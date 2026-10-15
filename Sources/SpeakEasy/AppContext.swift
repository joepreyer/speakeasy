import AppKit
import ApplicationServices
import SQLite3

struct DictationContext {
    var appName: String?
    var bundleID: String?
    var processID: pid_t?
    var isDeveloperApp = false
    var usesAtMentions = false
    var workspaceRoot: URL?

    var transcriptionPrompt: String? {
        guard let appName else { return nil }
        if isDeveloperApp {
            return "A software developer dictating into \(appName). Expect code identifiers, file names, CLI commands, and technical terms."
        }
        return "Dictation typed into \(appName)."
    }
}

/// Figures out where the dictation is going: the frontmost app, whether it's a developer
/// tool, and (for code editors) which workspace folder is open.
enum AppContext {
    /// VS Code-family editors and their Application Support folder names.
    private static let vscodeFamily: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
    ]

    private static let atMentionApps: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
    ]

    private static let developerApps: Set<String> = [
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "dev.zed.Zed",
        "com.sublimetext.4", "com.panic.Nova", "net.kovidgoyal.kitty", "io.alacritty",
        "com.github.wez.wezterm", "com.anthropic.claudefordesktop",
    ]

    private static let developerAppPrefixes = ["com.jetbrains.", "com.google.android.studio"]

    static func capture(developerMode: DeveloperMode) -> DictationContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return DictationContext() }
        let bundleID = app.bundleIdentifier ?? ""
        let isDevApp = developerApps.contains(bundleID)
            || developerAppPrefixes.contains { bundleID.hasPrefix($0) }

        var context = DictationContext()
        context.appName = app.localizedName
        context.bundleID = bundleID
        context.processID = app.processIdentifier
        context.usesAtMentions = atMentionApps.contains(bundleID)
        switch developerMode {
        case .auto: context.isDeveloperApp = isDevApp
        case .always: context.isDeveloperApp = true
        case .off: context.isDeveloperApp = false
        }
        return context
    }

    /// Best-effort: the git root of the focused window's document, else a recent
    /// VS Code-family workspace whose folder name appears in the window title.
    static func detectWorkspace(processID: pid_t, bundleID: String) -> URL? {
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Electron apps only expose their accessibility tree when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = copyAttribute(app, kAXFocusedWindowAttribute) else { return nil }
        let axWindow = window as! AXUIElement

        if let document = copyAttribute(axWindow, kAXDocumentAttribute) as? String,
           let url = URL(string: document), url.isFileURL,
           let root = gitRoot(containing: url) {
            return root
        }

        if let title = copyAttribute(axWindow, kAXTitleAttribute) as? String,
           let supportFolder = vscodeFamily[bundleID] {
            let parts = title
                .replacingOccurrences(of: " - ", with: " — ")
                .components(separatedBy: " — ")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "●"))) }
                .filter { !$0.isEmpty }
            for folder in recentFolders(supportFolder: supportFolder)
            where parts.contains(folder.lastPathComponent) {
                return folder
            }
        }
        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func gitRoot(containing file: URL) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        var dir = file.deletingLastPathComponent()
        while dir.path.count > 1, dir.standardizedFileURL.path != home {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private static func recentFolders(supportFolder: String) -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(supportFolder)/User/globalStorage")
        var uris: [String] = []

        if let data = try? Data(contentsOf: base.appendingPathComponent("storage.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let windows = json["windowsState"] as? [String: Any] {
            if let last = windows["lastActiveWindow"] as? [String: Any], let folder = last["folder"] as? String {
                uris.append(folder)
            }
            for window in windows["openedWindows"] as? [[String: Any]] ?? [] {
                if let folder = window["folder"] as? String { uris.append(folder) }
            }
        }

        if let value = readStateValue(db: base.appendingPathComponent("state.vscdb").path,
                                      key: "history.recentlyOpenedPathsList"),
           let json = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] {
            for entry in json["entries"] as? [[String: Any]] ?? [] {
                if let folder = entry["folderUri"] as? String { uris.append(folder) }
            }
        }

        var seen = Set<String>()
        return uris.compactMap { URL(string: $0) }
            .filter { $0.isFileURL && seen.insert($0.path).inserted }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func readStateValue(db path: String, key: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}

/// Lists source files in a workspace, cached briefly so repeated dictations stay fast.
final class FileIndex {
    static let shared = FileIndex()

    private let queue = DispatchQueue(label: "speakeasy.file-index")
    private var cache: [String: (date: Date, files: [String])] = [:]
    private let maxFiles = 30_000

    private static let skippedDirectories: Set<String> = [
        "node_modules", "build", "dist", "out", "target", "vendor", "coverage", "Pods",
        "DerivedData", "__pycache__", "venv", "env",
    ]

    /// Workspace-relative paths.
    func files(in root: URL) -> [String] {
        queue.sync {
            if let cached = cache[root.path], Date().timeIntervalSince(cached.date) < 120 {
                return cached.files
            }
            let files = list(root)
            cache[root.path] = (Date(), files)
            return files
        }
    }

    private func list(_ root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootPath = root.standardizedFileURL.path + "/"
        var files: [String] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if Self.skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            let path = url.standardizedFileURL.path
            files.append(path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent)
            if files.count >= maxFiles { break }
        }
        return files
    }
}

enum FileMatcher {
    /// Workspace files whose name (ignoring case, spacing, and punctuation) appears in the transcript.
    static func candidates(in transcript: String, files: [String], limit: Int = 25) -> [String] {
        let spoken = normalize(transcript.lowercased().replacingOccurrences(of: " dot ", with: "."))
        guard !spoken.isEmpty else { return [] }

        var matches: [(path: String, score: Int)] = []
        for path in files {
            let stem = normalize(((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased())
            guard stem.count >= 4, spoken.contains(stem) else { continue }
            matches.append((path, stem.count))
        }
        return matches.sorted { $0.score > $1.score }.prefix(limit).map(\.path)
    }

    private static func normalize(_ string: String) -> String {
        String(string.filter { $0.isLetter || $0.isNumber })
    }
}
