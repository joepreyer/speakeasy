import XCTest
@testable import SpeakEasy

final class UpdaterTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(Updater.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(Updater.isNewer("1.10.0", than: "1.9.3"))
        XCTAssertTrue(Updater.isNewer("2.0", than: "1.9.9"))
    }

    func testSameOrOlderVersions() {
        XCTAssertFalse(Updater.isNewer("1.0.1", than: "1.0.1"))
        XCTAssertFalse(Updater.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(Updater.isNewer("0.9.9", than: "1.0.0"))
    }
}
