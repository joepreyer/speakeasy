import AppKit
import Combine

/// Checks GitHub Releases for a newer version and installs it in place.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let downloadURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var state: State = .idle
    @Published var checksAutomatically: Bool {
        didSet { UserDefaults.standard.set(checksAutomatically, forKey: "checksForUpdates") }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/joepreyer/speakeasy/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/joepreyer/speakeasy/releases/latest")!
    private var timer: Timer?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Development builds run from the repo; replacing them with a release would be surprising.
    var isInstalledCopy: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    private init() {
        checksAutomatically = UserDefaults.standard.object(forKey: "checksForUpdates") as? Bool ?? true
    }

    func startAutomaticChecks() {
        guard isInstalledCopy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfEnabled() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfEnabled()
        }
    }

    private func checkIfEnabled() {
        if checksAutomatically { check() }
    }

    func check() {
        guard state != .checking, state != .downloading else { return }
        state = .checking
        Task { @MainActor in
            do {
                let release = try await Self.fetchLatest()
                if Self.isNewer(release.version, than: currentVersion) {
                    available = release
                    state = .idle
                } else {
                    available = nil
                    state = .upToDate
                }
            } catch {
                state = .failed("Couldn't check for updates.")
            }
        }
    }

    /// Downloads the new version, swaps it in after this process exits, and relaunches.
    func install() {
        guard let release = available, state != .downloading else { return }
        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        state = .downloading
        Task { @MainActor in
            do {
                let newApp = try await Self.download(release)
                try Self.replace(appURL, with: newApp)
                NSApp.terminate(nil)
            } catch {
                state = .failed("Update failed. You can download it from GitHub instead.")
            }
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(available?.pageURL ?? Self.releasesPage)
    }

    // MARK: Networking

    private static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { $0["name"] as? String == "SpeakEasy.zip" }),
              let download = (zip["browser_download_url"] as? String).flatMap(URL.init(string:))
        else { throw URLError(.badServerResponse) }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, pageURL: page, downloadURL: download)
    }

    private static func download(_ release: Release) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("speakeasy-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", file.path, folder.path])

        let app = folder.appendingPathComponent("SpeakEasy.app")
        try run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        guard Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw URLError(.cannotDecodeContentData)
        }
        return app
    }

    /// The copy happens in a detached shell so it can wait for this process to quit first.
    private static func replace(_ appURL: URL, with newApp: URL) throws {
        let script = """
        while kill -0 "$0" 2>/dev/null; do sleep 0.2; done
        rm -rf "$1.updating"
        /usr/bin/ditto "$2" "$1.updating" && rm -rf "$1" && mv "$1.updating" "$1"
        /usr/bin/open "$1"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier), appURL.path, newApp.path]
        try task.run()
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw URLError(.cannotDecodeContentData) }
    }

    // MARK: Versions


    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

enum UpdateConfirmation {
    static func present() {
        let updater = Updater.shared
        guard let release = updater.available else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update to SpeakEasy \(release.version)?"
        alert.informativeText = "You have \(updater.currentVersion). SpeakEasy will restart to finish. Your history, dictionary, and settings stay as they are, but macOS may ask you to allow SpeakEasy's permissions again."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "What's New")
        switch alert.runModal() {
        case .alertFirstButtonReturn: updater.install()
        case .alertThirdButtonReturn: updater.openReleasePage()
        default: break
        }
    }
}
