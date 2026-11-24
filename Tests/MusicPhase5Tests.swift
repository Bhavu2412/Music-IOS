import SwiftData
import UIKit
import XCTest
@testable import Music

@MainActor
final class MusicPhase5Tests: XCTestCase {
    func testMergeOfThreeCopiesKeepsHighestBitrateAndRepointsPlaylists() throws {
        let container = try ModelContainer(
            for: Track.self, Playlist.self, Album.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let low = Track(title: "Song", artist: "A", duration: 200, bookmarkData: Data(), originalFilename: "1.mp3", bitrate: 128_000)
        let mid = Track(title: "song ", artist: "a", duration: 201, bookmarkData: Data(), originalFilename: "2.mp3", bitrate: 192_000)
        let high = Track(title: "SONG", artist: "A", duration: 199, bookmarkData: Data(), originalFilename: "3.mp3", bitrate: 320_000)
        [low, mid, high].forEach(context.insert)
        let playlist = Playlist(name: "Mix", trackIDs: [low.id, mid.id, high.id])
        context.insert(playlist)

        let service = MergeService()
        let pairs = service.detectDuplicateTracks(in: [low, mid, high])
        XCTAssertEqual(pairs.count, 3)
        let deleted = try service.mergeDuplicateTracks(pairs, in: context)

        XCTAssertEqual(deleted, [low.id, mid.id])
        XCTAssertEqual(playlist.trackIDs, [high.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 1)
    }

    func testURLValidationOnlyAcceptsHTTP() {
        let viewModel = URLImportViewModel()
        viewModel.urlText = "  https://example.com/a.mp3  "
        XCTAssertTrue(viewModel.validateURL())
        viewModel.urlText = "file:///private/a.mp3"
        XCTAssertFalse(viewModel.validateURL())
        XCTAssertFalse(viewModel.isURLValid)
        viewModel.urlText = "ftp://example.com/a.mp3"
        XCTAssertFalse(viewModel.validateURL())
    }

    func testDownloadedFileExtensionFromMIMEType() {
        XCTAssertEqual(DownloadService.fileExtension(forMIMEType: "audio/x-m4a"), "m4a")
        XCTAssertEqual(DownloadService.fileExtension(forMIMEType: "audio/flac"), "flac")
        XCTAssertEqual(DownloadService.fileExtension(forMIMEType: nil), "mp3")
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

    func testLyricsParsing() {
        guard case .synced(let lines) = LyricsService.parse("[00:01.50]Hello\n[00:03.00][00:10.00]Chorus\n[ar:Artist]") else {
            return XCTFail("LRC should parse as synced")
        }
        XCTAssertEqual(lines.map(\.time), [1.5, 3, 10])
        XCTAssertEqual(lines.map(\.text), ["Hello", "Chorus", "Chorus"])
        XCTAssertEqual(LyricsService.parse("just words\nmore"), .plain("just words\nmore"))
        XCTAssertNil(LyricsService.parse("   "))
    }

    func testLiveActivityPayloadFitsActivityKitLimit() throws {
        // A big, noisy image: the worst case for JPEG size.
        let big = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1200)).jpegData(withCompressionQuality: 1) { ctx in
            for i in 0..<400 {
                UIColor(hue: CGFloat(i % 37) / 37, saturation: 1, brightness: 1, alpha: 1).setFill()
                ctx.fill(CGRect(x: (i * 53) % 1200, y: (i * 97) % 1200, width: 60, height: 60))
            }
        }
        let state = NowPlayingAttributes.ContentState(
            track: String(repeating: "Long Song Title ", count: 6),
            artist: String(repeating: "Artist ", count: 6),
            artworkData: LiveActivityService.thumbnail(big),
            isPlaying: true
        )
        let payload = try JSONEncoder().encode(state)
        XCTAssertLessThan(payload.count, 4096, "ActivityKit rejects content over 4 KB")
    }
}
