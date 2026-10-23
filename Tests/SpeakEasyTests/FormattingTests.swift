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

final class FormattingGateTests: XCTestCase {
    func testSkipsShortCleanTranscripts() {
        XCTAssertFalse(Formatter.needsFormatting("Sounds good, see you then.", context: DictationContext()))
    }

    func testFormatsFillersCorrectionsAndSpokenPunctuation() {
        let context = DictationContext()
        XCTAssertTrue(Formatter.needsFormatting("Um, see you then.", context: context))
        XCTAssertTrue(Formatter.needsFormatting("Let's meet Monday, actually Tuesday.", context: context))
        XCTAssertTrue(Formatter.needsFormatting("See you then question mark", context: context))
    }

    func testFormatsNumberWordsAndRepeats() {
        let context = DictationContext()
        XCTAssertTrue(Formatter.needsFormatting("See you at seven.", context: context))
        XCTAssertTrue(Formatter.needsFormatting("I think the the plan works.", context: context))
    }

    func testFormatsLongOrLowercaseTranscripts() {
        let context = DictationContext()
        let long = "This is a perfectly clean sentence that simply has more words than the short limit allows."
        XCTAssertTrue(Formatter.needsFormatting(long, context: context))
        XCTAssertTrue(Formatter.needsFormatting("sounds good.", context: context))
    }

    func testAlwaysFormatsInDeveloperApps() {
        var context = DictationContext()
        context.isDeveloperApp = true
        XCTAssertTrue(Formatter.needsFormatting("Run the tests.", context: context))
    }

    func testDropsFinalPeriodInChatApps() {
        var context = DictationContext()
        context.bundleID = "com.tinyspeck.slackmacgap"
        XCTAssertEqual(Formatter.unformatted("Sounds good, see you then.", context: context), "Sounds good, see you then")
        XCTAssertEqual(Formatter.unformatted("Sounds good. See you then.", context: context), "Sounds good. See you then.")
        XCTAssertEqual(Formatter.unformatted("Sounds good.", context: DictationContext()), "Sounds good.")
    }
}
