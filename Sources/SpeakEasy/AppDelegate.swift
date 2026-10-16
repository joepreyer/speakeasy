import AppKit
import ApplicationServices
import AVFoundation
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = FnKeyMonitor()
    private let recorder = Recorder()
    private let overlay = OverlayController()
    private let learner = CorrectionLearner()
    private let mainWindow = MainWindowController()
    private lazy var onboarding = OnboardingWindowController(
        isMonitorRunning: { [weak self] in self?.monitor.isRunning ?? false },
        startMonitor: { [weak self] in self?.monitor.start() ?? false },
        onFinish: { [weak self] in self?.mainWindow.show() }
    )
    private let store = AppStore.shared
    private let settings = Settings.shared
    private var statusItem: NSStatusItem?
    private let updateMenuItem = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
    private var updateObserver: AnyCancellable?
    private var contextTask: Task<DictationContext, Never>?

    // Holding fn for less than this is treated as an accidental tap.
    private let minimumRecordingDuration: TimeInterval = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        overlay.levelProvider = { [weak self] in self?.recorder.level ?? 0 }
        learner.isKnown = { [weak self] word in self?.store.containsTerm(word) ?? false }
        learner.onLearn = { [weak self] words in self?.learned(words) }

        monitor.onFnDown = { [weak self] in self?.beginDictation() }
        monitor.onFnUp = { [weak self] in self?.endDictation() }
        monitor.onOtherKeyWhileFnHeld = { [weak self] in self?.cancelDictation() }
        monitor.start()

        let setUp = UserDefaults.standard.bool(forKey: "onboardingComplete")
            && Permissions.allGranted
            && monitor.isRunning
            && Keychain.loadAPIKey() != nil
        if setUp {
            overlay.flash(.info("SpeakEasy is ready. Hold fn to talk."))
        } else {
            onboarding.show()
        }

        Updater.shared.startAutomaticChecks()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboarding.isVisible {
            onboarding.show()
        } else {
            mainWindow.show()
        }
        return true
    }

    // MARK: - Dictation flow

    private func beginDictation() {
        guard Keychain.loadAPIKey() != nil, Permissions.isGranted(.microphone) else {
            onboarding.show()
            return
        }
        guard !recorder.isRecording else { return }
        learner.finish()
        do {
            try recorder.start()
            overlay.show(.listening)
        } catch {
            overlay.flash(.error(error.localizedDescription))
            return
        }

        // Workspace detection and file indexing run while the user is still talking.
        let base = AppContext.capture(developerMode: settings.developerMode)
        let wantsWorkspace = base.isDeveloperApp && settings.tagFiles && settings.smartFormatting
        contextTask = Task.detached(priority: .userInitiated) {
            var context = base
            if wantsWorkspace, let pid = context.processID, let bundleID = context.bundleID,
               let root = AppContext.detectWorkspace(processID: pid, bundleID: bundleID) {
                context.workspaceRoot = root
                _ = FileIndex.shared.files(in: root)
            }
            return context
        }
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        let duration = recorder.duration

        if duration < minimumRecordingDuration {
            recorder.cancel()
            overlay.hide()
            contextTask = nil
            return
        }

        guard let audioURL = recorder.stop(), let apiKey = Keychain.loadAPIKey() else {
            overlay.hide()
            return
        }
        overlay.show(.processing)
        let pendingContext = contextTask
        contextTask = nil

        Task { @MainActor in
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let context = await pendingContext?.value ?? DictationContext()
            do {
                let output = try await DictationPipeline.run(audio: audioURL, context: context, apiKey: apiKey)
                guard !output.text.isEmpty else {
                    if !recorder.isRecording { overlay.hide() }
                    return
                }
                insert(output.text)
                store.add(Dictation(
                    id: UUID(),
                    date: Date(),
                    rawText: output.raw,
                    text: output.text,
                    duration: duration,
                    appName: context.appName
                ))
            } catch {
                if !recorder.isRecording { overlay.flash(.error(error.localizedDescription)) }
            }
        }
    }

    private func insert(_ text: String) {
        guard AXIsProcessTrusted() else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if !recorder.isRecording {
                overlay.flash(.error("Copied. Allow Accessibility to insert text automatically."))
            }
            return
        }
        if !recorder.isRecording { overlay.hide() }
        Paster.paste(text)
        if settings.learnCorrections {
            learner.watch(inserted: text)
        }
    }

    private func cancelDictation() {
        guard recorder.isRecording else { return }
        recorder.cancel()
        contextTask = nil
        overlay.hide()
    }

    private func learned(_ words: [String]) {
        let added = words.filter { store.addTerm($0, learned: true) }
        guard !added.isEmpty, !overlay.isShowingActivity else { return }
        let list = added.map { "“\($0)”" }.joined(separator: ", ")
        overlay.flash(.info("Added \(list) to your dictionary"))
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "SpeakEasy"
        item.button?.image = icon

        let menu = NSMenu()
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        menu.addItem(updateMenuItem)
        updateObserver = Updater.shared.$available
            .combineLatest(Updater.shared.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] release, state in
                guard let self else { return }
                self.updateMenuItem.isHidden = release == nil
                if let release {
                    self.updateMenuItem.title = state == .downloading
                        ? "Downloading update…"
                        : "Update to SpeakEasy \(release.version)…"
                }
            }

        let items = [
            NSMenuItem(title: "Open SpeakEasy", action: #selector(openMainWindow), keyEquivalent: ""),
            NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","),
            NSMenuItem(title: "Setup Assistant…", action: #selector(openOnboarding), keyEquivalent: ""),
        ]
        for menuItem in items {
            menuItem.target = self
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SpeakEasy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openMainWindow() {
        mainWindow.show()
    }

    @objc private func openSettings() {
        mainWindow.show(page: .settings)
    }

    @objc private func openOnboarding() {
        onboarding.show()
    }

    @objc private func installUpdate() {
        mainWindow.show(page: .home)
        UpdateConfirmation.present()
    }
}
