import AppKit

// Used by the uninstaller before it removes the app.
if CommandLine.arguments.contains("--unregister-login-item") {
    Permissions.setLaunchesAtLogin(false)
    exit(0)
}

// `SpeakEasy --dictate-file <audio> [--app <bundle id>]` runs the transcription and
// formatting pipeline on a file and prints the result, for testing without a microphone.
if let index = CommandLine.arguments.firstIndex(of: "--dictate-file"),
   CommandLine.arguments.count > index + 1 {
    let args = CommandLine.arguments
    let audio = URL(fileURLWithPath: args[index + 1])
    var context = DictationContext()
    if let appIndex = args.firstIndex(of: "--app"), args.count > appIndex + 1 {
        let bundleID = args[appIndex + 1]
        context.bundleID = bundleID
        context.appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
        context.isDeveloperApp = Settings.shared.developerMode != .off
        context.usesAtMentions = ["com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"].contains(bundleID)
    }
    if let rootIndex = args.firstIndex(of: "--workspace"), args.count > rootIndex + 1 {
        context.workspaceRoot = URL(fileURLWithPath: args[rootIndex + 1])
    }
    guard let apiKey = Keychain.loadAPIKey() else {
        print("No API key in Keychain")
        exit(1)
    }
    Task {
        do {
            let output = try await DictationPipeline.run(audio: audio, context: context, apiKey: apiKey)
            print("RAW:\n\(output.raw)\n\nFORMATTED:\n\(output.text)")
            exit(0)
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Accessory apps get no default main menu. These menus make Cmd+Q/W/C/V/etc. work
// in the app's own windows and dialogs.
let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Hide SpeakEasy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Quit SpeakEasy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu

let editItem = NSMenuItem()
mainMenu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu

let windowItem = NSMenuItem()
mainMenu.addItem(windowItem)
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
windowItem.submenu = windowMenu
app.windowsMenu = windowMenu

app.mainMenu = mainMenu
app.run()
