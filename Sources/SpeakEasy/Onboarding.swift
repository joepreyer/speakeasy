import AppKit
import SwiftUI

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: OnboardingModel

    init(isMonitorRunning: @escaping () -> Bool, startMonitor: @escaping () -> Bool, onFinish: @escaping () -> Void) {
        model = OnboardingModel(isMonitorRunning: isMonitorRunning, startMonitor: startMonitor, onFinish: onFinish)
        super.init()
        model.close = { [weak self] in self?.window?.close() }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Set up SpeakEasy"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            window.center()
            self.window = window
        }
        model.resume()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.pause()
        AppWindows.updateActivationPolicy(closing: window)
    }
}

/// Shows the Dock icon only while one of the app's windows is open.
enum AppWindows {
    static func updateActivationPolicy(closing: NSWindow?) {
        DispatchQueue.main.async {
            let anyOpen = NSApp.windows.contains {
                $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
            }
            if !anyOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, apiKey, fnKey, tryIt
}

final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep {
        didSet { UserDefaults.standard.set(step.rawValue, forKey: "onboardingStep") }
    }
    @Published private(set) var granted: [Permission: Bool] = [:]
    @Published private(set) var monitorRunning = false
    @Published private(set) var fnKeyIsFree = false
    @Published private(set) var hasKey = Keychain.loadAPIKey() != nil
    @Published var keyInput = ""
    @Published private(set) var validatingKey = false
    @Published private(set) var keyError: String?
    @Published var practiceText = ""
    @Published var launchAtLogin = true

    var close: (() -> Void)?
    private let isMonitorRunning: () -> Bool
    private let startMonitor: () -> Bool
    private let onFinish: () -> Void
    private var timer: Timer?

    init(isMonitorRunning: @escaping () -> Bool, startMonitor: @escaping () -> Bool, onFinish: @escaping () -> Void) {
        self.isMonitorRunning = isMonitorRunning
        self.startMonitor = startMonitor
        self.onFinish = onFinish
        let saved = OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: "onboardingStep")) ?? .welcome
        step = saved
        refresh()
        if saved != .welcome, !allPermissionsReady { step = .permissions }
    }

    var allPermissionsReady: Bool {
        Permission.allCases.allSatisfy { granted[$0] == true } && monitorRunning
    }

    /// Input Monitoring is granted but this process can't see the fn key until it restarts.
    var needsRestart: Bool {
        granted[.inputMonitoring] == true && !monitorRunning
    }

    func resume() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        var updated: [Permission: Bool] = [:]
        for permission in Permission.allCases { updated[permission] = Permissions.isGranted(permission) }
        if updated != granted { granted = updated }
        if updated[.inputMonitoring] == true, !isMonitorRunning() { _ = startMonitor() }
        let running = isMonitorRunning()
        if running != monitorRunning { monitorRunning = running }
        let free = Permissions.fnKeyIsFree
        if free != fnKeyIsFree { fnKeyIsFree = free }
    }

    func next() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = next }
        }
    }

    func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = previous }
        }
    }

    func connectKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validatingKey = true
        keyError = nil
        Task { @MainActor in
            do {
                try await OpenAI.validate(apiKey: key)
                Keychain.saveAPIKey(key)
                hasKey = true
                keyInput = ""
            } catch {
                keyError = error.localizedDescription
            }
            validatingKey = false
        }
    }

    func replaceKey() {
        hasKey = false
    }

    func finish() {
        Permissions.setLaunchesAtLogin(launchAtLogin)
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        step = .permissions
        close?()
        onFinish()
    }
}

// MARK: - Views

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .permissions: PermissionsStep(model: model)
                case .apiKey: APIKeyStep(model: model)
                case .fnKey: FnKeyStep(model: model)
                case .tryIt: TryItStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 56)
            .padding(.top, 44)
            .transition(.opacity)

            if model.step != .welcome {
                footer
            }
        }
        .frame(width: 640, height: 600)
        .background(Theme.background)
    }

    private var footer: some View {
        HStack {
            Button("Back", action: model.back)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases.dropFirst(), id: \.self) { step in
                    Circle()
                        .fill(step == model.step ? Color.primary : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.step {
        case .welcome:
            EmptyView()
        case .permissions:
            PillButton(title: "Continue", enabled: model.allPermissionsReady, action: model.next)
        case .apiKey:
            PillButton(title: "Continue", enabled: model.hasKey, action: model.next)
        case .fnKey:
            PillButton(title: model.fnKeyIsFree ? "Continue" : "Skip", enabled: true, action: model.next)
        case .tryIt:
            PillButton(title: "Finish", enabled: true, action: model.finish)
        }
    }
}

private struct PillButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(enabled ? Color(nsColor: .windowBackgroundColor) : .secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(enabled ? Color.primary : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
    }
}

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
    }
}

private struct WelcomeStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            VStack(spacing: 10) {
                Text("Welcome to SpeakEasy")
                    .font(.system(size: 30, weight: .semibold))
                Text("Hold fn, say what you want to write, and let go.\nYour words appear wherever you're typing.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
            PillButton(title: "Get started", enabled: true, action: model.next)
            Text("Setup takes about a minute.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 36)
        }
    }
}

private struct PermissionsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                title: "Allow a few permissions",
                subtitle: "macOS asks you to approve these yourself. Click Allow, switch SpeakEasy on in the window that opens, then come back here."
            )

            Card {
                ForEach(Array(Permission.allCases.enumerated()), id: \.element) { index, permission in
                    if index > 0 { Divider() }
                    row(permission)
                }
            }

            Label("SpeakEasy only listens while you hold fn. Audio goes straight to OpenAI for transcription, and your history stays on this Mac.",
                  systemImage: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func row(_ permission: Permission) -> some View {
        HStack(spacing: 14) {
            Image(systemName: permission.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.selection))
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(permission == .inputMonitoring && model.needsRestart
                     ? "Almost there: SpeakEasy needs to restart to finish."
                     : permission.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if permission == .inputMonitoring && model.needsRestart {
                Button("Restart") { Permissions.relaunch() }
            } else if model.granted[permission] == true {
                StatusBadge(text: "Allowed")
            } else {
                Button("Allow") { Permissions.request(permission) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct APIKeyStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                title: "Connect OpenAI",
                subtitle: "SpeakEasy uses OpenAI's speech models with your own API key. You pay OpenAI directly, usually a few cents per hour of dictation."
            )

            if model.hasKey {
                Card {
                    HStack {
                        StatusBadge(text: "Your API key is saved in the Keychain")
                        Spacer()
                        Button("Use a different key", action: model.replaceKey)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        SecureField("Paste your API key (sk-…)", text: $model.keyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                            .onSubmit(model.connectKey)
                        if model.validatingKey {
                            ProgressView().controlSize(.small).frame(width: 70)
                        } else {
                            Button("Connect", action: model.connectKey)
                                .controlSize(.large)
                                .disabled(model.keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let error = model.keyError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Label("Get an API key from OpenAI", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                }
            }

            Label("Your key is stored in the macOS Keychain and only sent to OpenAI.", systemImage: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct FnKeyStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                title: "Free up the fn key",
                subtitle: "macOS uses the fn (🌐) key for its own shortcuts by default. Set it to Do Nothing so holding fn starts SpeakEasy instead."
            )

            Card {
                HStack {
                    Text("Press 🌐 key to")
                        .font(.system(size: 14))
                    Spacer()
                    Text("Do Nothing")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.selection))
                }
                .padding(20)
            }

            if model.fnKeyIsFree {
                StatusBadge(text: "fn is ready for SpeakEasy")
            } else {
                Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                    .controlSize(.large)
                Text("You'll find it near the top of the Keyboard settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct TryItStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                title: "Try it out",
                subtitle: "Click in the box, hold fn, say something, and let go."
            )

            TextEditor(text: $model.practiceText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))

            if !model.practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StatusBadge(text: "That's it. It works in any app.")
            }

            Toggle("Open SpeakEasy when I log in", isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
                .font(.system(size: 13))

            Text("SpeakEasy lives in your menu bar. Click its icon to see your history, dictionary, and settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
