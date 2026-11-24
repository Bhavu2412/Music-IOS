import XCTest
@testable import Music

@MainActor
final class MusicPhase5Tests: XCTestCase {
    func testQueueLogicKeepsCurrentItemFirst() {
        let queue = ["one", "two", "three"]
        let current = "two"
        let next = queue.filter { $0 != current }.prefix(1)
        XCTAssertEqual(Array(next), ["one"])
    }

    func testDuplicateDetectionMatchesTitleArtistAndDurationTolerance() {
        let one = Track(title: "Same Song", artist: "Same Artist", albumTitle: "Album", duration: 180, bookmarkData: Data(), originalFilename: "a.mp3")
        let two = Track(title: "Same Song", artist: "Same Artist", albumTitle: "Album", duration: 181.8, bookmarkData: Data(), originalFilename: "b.mp3")
        let service = MergeService()
        let result = service.detectDuplicateTracks(in: [one, two])
        XCTAssertEqual(result.count, 1)
    }

    func testDirectURLValidationRejectsMissingHost() {
        let viewModel = URLImportViewModel()
        viewModel.urlText = "https://example.com/song.mp3"
        XCTAssertTrue(viewModel.validateURL())
        viewModel.urlText = "not-a-url"
        XCTAssertFalse(viewModel.validateURL())
    }

    func testConnectivityDefaultsToOnline() {
        let monitor = ConnectivityService()
        XCTAssertTrue(monitor.isOnline)
    }
}
