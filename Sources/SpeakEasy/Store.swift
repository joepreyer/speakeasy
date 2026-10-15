import Foundation

struct Dictation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let rawText: String
    let text: String
    let duration: TimeInterval
    let appName: String?

    var wordCount: Int { Self.countWords(text) }
    var spokenWordCount: Int { Self.countWords(rawText) }

    static func countWords(_ string: String) -> Int {
        string.split(whereSeparator: { $0.isWhitespace }).count
    }
}

struct DictionaryTerm: Codable, Identifiable, Hashable {
    let id: UUID
    var term: String
    var learned: Bool
    let added: Date
}

/// Dictation history and the personal dictionary, persisted as JSON in Application Support.
final class AppStore: ObservableObject {
    static let shared = AppStore()

    /// Newest first.
    @Published private(set) var dictations: [Dictation] = []
    /// Newest first.
    @Published private(set) var terms: [DictionaryTerm] = []

    private let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var dictionaryURL: URL { directory.appendingPathComponent("dictionary.json") }

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakEasy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dictations = Self.load([Dictation].self, from: historyURL) ?? []
        terms = Self.load([DictionaryTerm].self, from: dictionaryURL) ?? []
    }

    // MARK: History

    func add(_ dictation: Dictation) {
        dictations.insert(dictation, at: 0)
        save(dictations, to: historyURL)
    }

    func deleteDictation(id: UUID) {
        dictations.removeAll { $0.id == id }
        save(dictations, to: historyURL)
    }

    var totalWords: Int { dictations.reduce(0) { $0 + $1.wordCount } }

    var averageWPM: Int {
        let timed = dictations.filter { $0.duration >= 1 }
        let minutes = timed.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return 0 }
        return Int((Double(timed.reduce(0) { $0 + $1.spokenWordCount }) / minutes).rounded())
    }

    /// Consecutive calendar weeks with at least one dictation, ending this week (or last week).
    var weekStreak: Int {
        let calendar = Calendar.current
        let weeks = Set(dictations.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(cursor) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    var wordsToday: Int {
        let calendar = Calendar.current
        return dictations.filter { calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: Dictionary

    func containsTerm(_ term: String) -> Bool {
        terms.contains { $0.term == term }
    }

    /// Adds a term, or updates the casing of an existing one. Returns false if nothing changed.
    @discardableResult
    func addTerm(_ raw: String, learned: Bool) -> Bool {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 60, !term.contains(where: { $0.isNewline }) else { return false }
        if let index = terms.firstIndex(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) {
            guard terms[index].term != term else { return false }
            terms[index].term = term
        } else {
            terms.insert(DictionaryTerm(id: UUID(), term: term, learned: learned, added: Date()), at: 0)
        }
        save(terms, to: dictionaryURL)
        return true
    }

    func removeTerm(id: UUID) {
        terms.removeAll { $0.id == id }
        save(terms, to: dictionaryURL)
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
