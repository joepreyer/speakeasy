import AppKit
import SwiftUI

final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(page: Page? = nil) {
        if let page { Navigation.shared.page = page }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "SpeakEasy"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: MainView()
                    .environmentObject(AppStore.shared)
                    .environmentObject(Settings.shared)
            )
            window.setFrameAutosaveName("SpeakEasyMain")
            if !window.setFrameUsingName("SpeakEasyMain") { window.center() }
            self.window = window
        }
        // Show in the Dock and app switcher while the window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.updateActivationPolicy(closing: window)
    }
}

final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var page: Page = .home
}

// MARK: - Theme

enum Theme {
    static let background = dynamic(light: NSColor(red: 0.98, green: 0.98, blue: 0.975, alpha: 1),
                                     dark: NSColor(white: 0.11, alpha: 1))
    static let sidebar = dynamic(light: NSColor(red: 0.955, green: 0.952, blue: 0.945, alpha: 1),
                                  dark: NSColor(white: 0.085, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 0.15, alpha: 1))
    static let hover = dynamic(light: NSColor(red: 0.965, green: 0.962, blue: 0.955, alpha: 1),
                                dark: NSColor(white: 0.19, alpha: 1))
    static let border = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.08))
    static let selection = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.08))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

// MARK: - Root

enum Page: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @ObservedObject private var navigation = Navigation.shared

    private var page: Page {
        get { navigation.page }
        nonmutating set { navigation.page = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch page {
                case .home: HomeView()
                case .dictionary: DictionaryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .frame(minWidth: 900, minHeight: 600)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("SpeakEasy")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 52)
            .padding(.bottom, 20)

            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 14, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(page == item ? Theme.selection : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Hold fn to dictate")
                    .font(.system(size: 12, weight: .medium))
                Text("Release to insert text wherever your cursor is.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.selection))
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .background(Theme.sidebar)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }

    private var groups: [(day: Date, items: [Dictation])] {
        let calendar = Calendar.current
        let needle = query.trimmingCharacters(in: .whitespaces)
        let filtered = needle.isEmpty
            ? store.dictations
            : store.dictations.filter { $0.text.localizedCaseInsensitiveContains(needle) }
        var result: [(day: Date, items: [Dictation])] = []
        for dictation in filtered {
            let day = calendar.startOfDay(for: dictation.date)
            if result.last?.day == day {
                result[result.count - 1].items.append(dictation)
            } else {
                result.append((day, [dictation]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Welcome back, \(firstName)")
                    .font(.system(size: 28, weight: .semibold))

                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 28) {
                        searchField
                        if groups.isEmpty {
                            emptyState
                        } else {
                            ForEach(groups, id: \.day) { group in
                                DaySection(day: group.day, items: group.items)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StatsCard()
                        .frame(width: 270)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search dictations", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(query.isEmpty ? "No dictations yet" : "No matches")
                    .font(.system(size: 16, weight: .semibold))
                Text(query.isEmpty
                     ? "Click into any text field, hold fn, and start talking. Everything you dictate shows up here."
                     : "Nothing you've dictated matches “\(query)”.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DaySection: View {
    let day: Date
    let items: [Dictation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.month(.wide).day().year()).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(.secondary)
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, dictation in
                    if index > 0 { Divider() }
                    DictationRow(dictation: dictation)
                }
            }
        }
    }
}

struct DictationRow: View {
    let dictation: Dictation
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false
    @State private var copied = false
    @State private var showOriginal = false

    private var isEdited: Bool { dictation.rawText != dictation.text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(dictation.date.formatted(.dateTime.hour().minute()).lowercased())
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(showOriginal ? dictation.rawText : dictation.text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showOriginal || dictation.appName != nil {
                    Text([showOriginal ? "Original transcript" : nil, dictation.appName]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 2) {
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")

                Menu {
                    Button(showOriginal ? "Show formatted text" : "Show original transcript") {
                        showOriginal.toggle()
                    }
                    .disabled(!isEdited)
                    Button("Copy original transcript") { write(dictation.rawText) }
                    Divider()
                    Button("Delete", role: .destructive) { store.deleteDictation(id: dictation.id) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(hovering ? Theme.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func copy() {
        write(showOriginal ? dictation.rawText : dictation.text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct StatsCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                stat(store.totalWords.formatted(), "total words")
                stat("\(store.averageWPM)", "wpm")
                stat("\(store.weekStreak)", store.weekStreak == 1 ? "week" : "weeks")
            }
            .padding(28)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                row("Today", "\(store.wordsToday.formatted()) words")
                row("Dictations", store.dictations.count.formatted())
                row("Dictionary", "\(store.terms.count) terms")
            }
            .padding(28)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(.system(size: 34, design: .serif))
            Text(label).font(.system(size: 15))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newTerm = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dictionary")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Names, jargon, and unusual spellings SpeakEasy should always get right. When you fix the spelling of a word right after dictating it, it's added here automatically.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 620, alignment: .leading)
                }

                HStack(spacing: 10) {
                    TextField("Add a word or phrase, e.g. Supabase", text: $newTerm)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .frame(maxWidth: 380)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .controlSize(.large)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Card {
                    if store.terms.isEmpty {
                        Text("No words yet.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(store.terms.enumerated()), id: \.element.id) { index, term in
                            if index > 0 { Divider() }
                            TermRow(term: term)
                        }
                    }
                }
                .frame(maxWidth: 620)
            }
            .padding(.horizontal, 48)
            .padding(.top, 56)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func add() {
        if store.addTerm(newTerm, learned: false) || store.containsTerm(newTerm.trimmingCharacters(in: .whitespaces)) {
            newTerm = ""
        }
    }
}

struct TermRow: View {
    let term: DictionaryTerm
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(term.term)
                .font(.system(size: 15))
                .textSelection(.enabled)
            if term.learned {
                Label("Learned", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            Spacer()
            Button {
                store.removeTerm(id: term.id)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(hovering ? Theme.hover : Color.clear)
        .onHover { hovering = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @State private var apiKey = ""
    @State private var hasKey = Keychain.loadAPIKey() != nil
    @State private var savedKey = false
    @State private var launchAtLogin = Permissions.launchesAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 28, weight: .semibold))
                .padding(.horizontal, 68)
                .padding(.top, 56)

                Form {
                    Section {
                        Toggle("Open SpeakEasy when I log in", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { Permissions.setLaunchesAtLogin($0) }
                    } header: {
                        Text("General")
                    }

                    Section {
                        HStack {
                            SecureField("API key", text: $apiKey, prompt: Text(hasKey ? "•••••••• (saved)" : "sk-…"))
                            Button(savedKey ? "Saved" : "Save") {
                                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else { return }
                                Keychain.saveAPIKey(key)
                                apiKey = ""
                                hasKey = true
                                savedKey = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedKey = false }
                            }
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("OpenAI")
                    } footer: {
                        Text(hasKey ? "Your key is stored in the macOS Keychain." : "Add your OpenAI API key to start dictating.")
                    }

                    Section {
                        TextField("Speech-to-text model", text: $settings.transcriptionModel,
                                  prompt: Text(Settings.defaultTranscriptionModel))
                    } header: {
                        Text("Transcription")
                    } footer: {
                        Text("Default: \(Settings.defaultTranscriptionModel). Your dictionary is sent along as vocabulary hints.")
                    }

                    Section {
                        Toggle("Smart formatting", isOn: $settings.smartFormatting)
                        TextField("Formatting model", text: $settings.formattingModel,
                                  prompt: Text(Settings.defaultFormattingModel))
                            .disabled(!settings.smartFormatting)
                    } header: {
                        Text("Formatting")
                    } footer: {
                        Text("Removes filler words, applies corrections (“2… actually 3”), spoken punctuation, and numbered lists. If formatting fails, the raw transcript is inserted instead.")
                    }

                    Section {
                        Picker("Developer mode", selection: $settings.developerMode) {
                            ForEach(DeveloperMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Toggle("Recognize workspace files (@-tag them in Cursor and Windsurf)", isOn: $settings.tagFiles)
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("Keeps code identifiers, CLI commands, and casing (camelCase, snake_case) intact, and spells technical terms correctly.")
                    }

                    Section {
                        Toggle("Learn from my spelling corrections", isOn: $settings.learnCorrections)
                    } header: {
                        Text("Dictionary")
                    } footer: {
                        Text("For 45 seconds after inserting text, SpeakEasy notices if you fix a word's spelling and adds the fix to your dictionary.")
                    }

                    Section {
                        Text("Hold fn to dictate. If macOS opens its own dictation or emoji picker, set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Shortcut")
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 720, maxHeight: .infinity)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
