import XCTest
@testable import SpeakEasy

final class FileMatcherTests: XCTestCase {
    private let files = [
        "Sources/SpeakEasy/AppDelegate.swift",
        "Sources/SpeakEasy/CorrectionLearner.swift",
        "Sources/SpeakEasy/main.swift",
        "README.md",
    ]

    func testMatchesSpokenFileNames() {
        let matches = FileMatcher.candidates(in: "update the app delegate dot swift file", files: files)
        XCTAssertEqual(matches, ["Sources/SpeakEasy/AppDelegate.swift"])
    }

    func testMatchesWithoutExtension() {
        let matches = FileMatcher.candidates(in: "look at the correction learner", files: files)
        XCTAssertEqual(matches, ["Sources/SpeakEasy/CorrectionLearner.swift"])
    }

    func testSkipsVeryShortNames() {
        XCTAssertEqual(FileMatcher.candidates(in: "fix the api call", files: ["src/api.ts"]), [])
    }
}

final class FormatterPromptTests: XCTestCase {
    func testForbidsEmDashes() {
        let prompt = Formatter.systemPrompt(context: DictationContext(), terms: [], files: [])
        XCTAssertTrue(prompt.contains("Never use em dashes"))
    }

    func testIncludesDictionaryTerms() {
        let prompt = Formatter.systemPrompt(context: DictationContext(), terms: ["Nuvio"], files: [])
        XCTAssertTrue(prompt.contains("Nuvio"))
    }

    func testTagsFilesInCursor() {
        var context = DictationContext()
        context.isDeveloperApp = true
        context.usesAtMentions = true
        let prompt = Formatter.systemPrompt(context: context, terms: [], files: ["App/AppDelegate.swift"])
        XCTAssertTrue(prompt.contains("@AppDelegate.swift"))
        XCTAssertTrue(prompt.contains("App/AppDelegate.swift"))
    }

    func testDeveloperRulesOnlyInDeveloperApps() {
        let prompt = Formatter.systemPrompt(context: DictationContext(), terms: [], files: [])
        XCTAssertFalse(prompt.contains("Developer context"))
    }
}
