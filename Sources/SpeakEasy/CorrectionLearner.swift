import AppKit
import ApplicationServices

/// After a paste, watches the focused text field for a short while. If the user fixes the
/// spelling of a word that was just dictated, reports the corrected spelling so it can be
/// added to the dictionary.
final class CorrectionLearner {
    var onLearn: (([String]) -> Void)?
    var isKnown: ((String) -> Bool)?

    private let watchDuration: TimeInterval = 45
    private let maxFieldLength = 50_000

    private var element: AXUIElement?
    private var baseline = ""
    private var latest = ""
    private var inserted = ""
    private var startedAt = Date()
    private var timer: Timer?
    private var pendingToken = UUID()

    func watch(inserted text: String) {
        finish()
        let token = UUID()
        pendingToken = token
        // Give the paste time to land before taking the baseline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.pendingToken == token else { return }
            self.begin(text)
        }
    }

    /// Stops watching and reports any corrections seen so far.
    func finish() {
        pendingToken = UUID()
        timer?.invalidate()
        timer = nil
        guard element != nil else { return }
        element = nil
        let words = Self.correctedWords(before: baseline, after: latest, inserted: inserted)
            .filter { !(isKnown?($0) ?? false) }
        if !words.isEmpty { onLearn?(words) }
    }

    private func begin(_ text: String) {
        guard let focused = Self.focusedElement(),
              let value = Self.value(of: focused),
              value.count <= maxFieldLength,
              value.contains(text)
        else { return }
        element = focused
        baseline = value
        latest = value
        inserted = text
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let element else { return }
        guard Date().timeIntervalSince(startedAt) < watchDuration,
              let focused = Self.focusedElement(), CFEqual(focused, element)
        else {
            finish()
            return
        }
        if let value = Self.value(of: element), value.count <= maxFieldLength {
            latest = value
        }
    }

    // MARK: Accessibility

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func value(of element: AXUIElement) -> String? {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == kAXSecureTextFieldSubrole { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: Diffing

    /// Corrected spellings from a small edit that overlaps the inserted text.
    static func correctedWords(before: String, after: String, inserted: String) -> [String] {
        guard before != after, let insertedRange = before.range(of: inserted) else { return [] }
        let old = Array(before), new = Array(after)

        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        // Widen the changed span to whole words.
        while prefix > 0, isWordCharacter(old[prefix - 1]) { prefix -= 1 }
        while suffix > 0, isWordCharacter(old[old.count - suffix]) { suffix -= 1 }

        let insertedStart = before.distance(from: before.startIndex, to: insertedRange.lowerBound)
        let insertedEnd = insertedStart + inserted.count
        guard prefix < insertedEnd, old.count - suffix > insertedStart else { return [] }

        let oldWords = words(in: String(old[prefix..<(old.count - suffix)]))
        let newWords = words(in: String(new[prefix..<(new.count - suffix)]))
        guard (1...3).contains(oldWords.count), (1...3).contains(newWords.count) else { return [] }

        let pairs: [(String, String)]
        if oldWords.count == newWords.count {
            pairs = Array(zip(oldWords, newWords))
        } else if newWords.count == 1 {
            pairs = [(oldWords.joined(), newWords[0])]
        } else {
            return []
        }
        return pairs.filter { isLikelySpellingFix(old: $0.0, new: $0.1) }.map(\.1)
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "'"
    }

    private static func words(in string: String) -> [String] {
        string.split(whereSeparator: { !isWordCharacter($0) }).map(String.init)
    }

    /// A respelling of a similar-sounding word into something that isn't an ordinary English word.
    private static func isLikelySpellingFix(old: String, new: String) -> Bool {
        guard old != new, (2...40).contains(new.count), new.contains(where: \.isLetter) else { return false }
        let a = old.lowercased(), b = new.lowercased()
        guard levenshtein(a, b) <= max(2, max(a.count, b.count) / 2) else { return false }

        let hasInnerCapitals = new.dropFirst().contains(where: \.isUppercase)
        if hasInnerCapitals { return true }
        let misspelled = NSSpellChecker.shared.checkSpelling(of: b, startingAt: 0).location != NSNotFound
        return misspelled
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
