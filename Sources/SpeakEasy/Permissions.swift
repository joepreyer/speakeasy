import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import ServiceManagement

enum Permission: CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var reason: String {
        switch self {
        case .microphone: return "Hears you while you hold fn. Nothing is recorded otherwise."
        case .accessibility: return "Types your words into the app you're using."
        case .inputMonitoring: return "Notices when you hold the fn key. SpeakEasy doesn't record other keys."
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .accessibility: return "character.cursor.ibeam"
        case .inputMonitoring: return "keyboard"
        }
    }

    fileprivate var settingsAnchor: String {
        switch self {
        case .microphone: return "Privacy_Microphone"
        case .accessibility: return "Privacy_Accessibility"
        case .inputMonitoring: return "Privacy_ListenEvent"
        }
    }
}

enum Permissions {
    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility:
            return AXIsProcessTrusted()
        case .inputMonitoring:
            // CGPreflightListenEventAccess can keep its launch-time answer; IOHIDCheckAccess asks again.
            return CGPreflightListenEventAccess() || IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    static var allGranted: Bool { Permission.allCases.allSatisfy(isGranted) }

    /// Shows the system prompt the first time; afterwards opens the matching System Settings pane.
    static func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                openSettings(for: permission)
            }
        case .accessibility:
            resetStaleEntry(service: "Accessibility")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
                openSettings(for: permission)
            }
        case .inputMonitoring:
            resetStaleEntry(service: "ListenEvent")
            if !CGRequestListenEventAccess() {
                openSettings(for: permission)
            }
        }
    }

    /// System Settings can list SpeakEasy as switched on while the grant belongs to a previous
    /// build with a different signature. Clearing the entry makes macOS add a fresh one for
    /// this build. Only called when the permission isn't working, so nothing valid is lost.
    private static func resetStaleEntry(service: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service, bundleID]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    static func openSettings(for permission: Permission) {
        open("x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)")
    }

    // MARK: fn key

    /// True when System Settings → Keyboard → "Press 🌐 key to" is "Do Nothing".
    static var fnKeyIsFree: Bool {
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int) == 0
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    // MARK: Launch at login

    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SpeakEasy: couldn't update login item: \(error.localizedDescription)")
        }
    }

    // MARK: Relaunch

    /// Some permissions only take effect in a fresh process.
    static func relaunch() {
        UserDefaults.standard.synchronize()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$1\"",
            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Ad-hoc builds get a new code signature every release, so grants saved for the
    /// previous build no longer apply to this one.
    static func isAdHocSigned(_ appURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
