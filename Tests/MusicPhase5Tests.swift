import SwiftData
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

    func testCloudSyncMergesAcrossDevicesByTitleAndArtist() throws {
        func device() throws -> (ModelContext, Track, Track) {
            let container = try ModelContainer(for: Track.self, Playlist.self, Album.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            // Same songs, different IDs per device (as after importing separately).
            let a = Track(title: "Song A", artist: "Band", bookmarkData: Data(), originalFilename: "a.mp3")
            let b = Track(title: "Song B", artist: "Band", bookmarkData: Data(), originalFilename: "b.mp3")
            context.insert(a); context.insert(b)
            return (context, a, b)
        }
        let (phone, phoneA, phoneB) = try device()
        let (pad, padA, padB) = try device()
        let t0 = Date(timeIntervalSince1970: 1_000)

        // Phone: favorite A, make a playlist [B, A].
        phoneA.isFavorite = true
        let mix = Playlist(name: "Mix", trackIDs: [phoneB.id, phoneA.id])
        phone.insert(mix)
        let phoneState = CloudState.local(tracks: [phoneA, phoneB], playlists: [mix], since: CloudState(), now: t0)

        // iPad pulls it.
        let padState = CloudState.local(tracks: [padA, padB], playlists: [], since: CloudState(), now: t0)
        let merged = padState.merged(with: phoneState)
        merged.apply(to: [padA, padB], playlists: [], in: pad)
        XCTAssertTrue(padA.isFavorite)
        let padPlaylists = try pad.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(padPlaylists.first?.trackIDs, [padB.id, padA.id])

        // iPad deletes the playlist later; the tombstone wins on the phone.
        let afterDelete = CloudState.local(tracks: [padA, padB], playlists: [], since: merged, now: t0.addingTimeInterval(60))
        afterDelete.merged(with: phoneState).apply(to: [phoneA, phoneB], playlists: [mix], in: phone)
        try phone.save()
        XCTAssertTrue(try phone.fetch(FetchDescriptor<Playlist>()).isEmpty, "tombstone should delete the playlist")
    }
}
