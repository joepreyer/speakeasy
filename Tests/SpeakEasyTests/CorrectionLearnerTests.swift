import XCTest
@testable import SpeakEasy

final class CorrectionLearnerTests: XCTestCase {
    private func learned(_ before: String, _ after: String, inserted: String? = nil) -> [String] {
        CorrectionLearner.correctedWords(before: before, after: after, inserted: inserted ?? before)
    }

    func testLearnsRespelledName() {
        XCTAssertEqual(learned("Hi! Send it to Nuveo today.", "Hi! Send it to Nuvio today.",
                               inserted: "Send it to Nuveo today."), ["Nuvio"])
    }

    func testLearnsMergedWords() {
        XCTAssertEqual(learned("Add a super base client.", "Add a Supabase client."), ["Supabase"])
    }

    func testLearnsCapitalization() {
        XCTAssertEqual(learned("use supabase here", "use Supabase here"), ["Supabase"])
    }

    func testLearnsIdentifier() {
        XCTAssertEqual(learned("call get user id", "call getUserId"), ["getUserId"])
    }

    func testIgnoresTypoFixOfCommonWord() {
        XCTAssertEqual(learned("fix teh bug", "fix the bug"), [])
    }

    func testIgnoresRewording() {
        XCTAssertEqual(learned("I am happy now", "I am glad now"), [])
    }

    func testIgnoresNumbers() {
        XCTAssertEqual(learned("meet at 3", "meet at 4"), [])
    }

    func testIgnoresEditsOutsideDictatedText() {
        XCTAssertEqual(learned("Old Nuveo text. New text here.", "Old Nuvio text. New text here.",
                               inserted: "New text here."), [])
    }

    func testIgnoresAppendedText() {
        XCTAssertEqual(learned("Hello there", "Hello there and more words added"), [])
    }
}
