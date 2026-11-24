import AVFoundation
import XCTest
@testable import Music

@MainActor
final class AudioEnginePlayerTests: XCTestCase {
    /// Writes a mono sine tone to a temporary .caf file.
    private func makeTone(seconds: Double, frequency: Double = 440) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = Float(sin(2 * .pi * frequency * Double(i) / format.sampleRate)) * 0.2
        }
        try file.write(from: buffer)
        return url
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func testPlaySeekPause() async throws {
        let player = AudioEnginePlayer()
        try player.load(try makeTone(seconds: 3), at: 0, autoplay: true)
        XCTAssertEqual(player.duration, 3, accuracy: 0.01)
        await wait(0.6)
        XCTAssertGreaterThan(player.currentTime, 0.2, "time should advance while playing")

        player.seek(to: 2)
        XCTAssertEqual(player.currentTime, 2, accuracy: 0.15)

        player.pause()
        let paused = player.currentTime
        await wait(0.4)
        XCTAssertEqual(player.currentTime, paused, accuracy: 0.001, "time must hold while paused")
        XCTAssertFalse(player.isPlaying)
    }

    func testRestoreLoadsPausedAtPosition() throws {
        let player = AudioEnginePlayer()
        try player.load(try makeTone(seconds: 3), at: 1.5, autoplay: false)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 1.5, accuracy: 0.01)
    }

    func testGaplessHandOffAndFinish() async throws {
        let player = AudioEnginePlayer()
        var advanced = false
        var finished = false
        player.onAdvancedToQueued = { advanced = true }
        player.onFinished = { finished = true }

        try player.load(try makeTone(seconds: 0.6), at: 0, autoplay: true)
        XCTAssertTrue(player.queueNext(try makeTone(seconds: 0.6, frequency: 660)))
        await wait(1.0)
        XCTAssertTrue(advanced, "queued file should take over without a reload")
        XCTAssertEqual(player.duration, 0.6, accuracy: 0.01)
        await wait(0.8)
        XCTAssertTrue(finished, "should report the end when nothing is queued")
    }

    func testClearQueuedKeepsPosition() async throws {
        let player = AudioEnginePlayer()
        var advanced = false
        player.onAdvancedToQueued = { advanced = true }
        try player.load(try makeTone(seconds: 1.5), at: 0, autoplay: true)
        player.queueNext(try makeTone(seconds: 1))
        await wait(0.3)
        let before = player.currentTime
        player.clearQueued()
        XCTAssertEqual(player.currentTime, before, accuracy: 0.1)
        XCTAssertNil(player.queuedURL)
        await wait(1.5)
        XCTAssertFalse(advanced, "a cleared file must not play")
    }

    func testCrossfadeSwitchesFile() async throws {
        let player = AudioEnginePlayer()
        var finished = false
        player.onFinished = { finished = true }
        try player.load(try makeTone(seconds: 2), at: 0, autoplay: true)
        await wait(0.3)
        try player.crossfade(to: try makeTone(seconds: 1), duration: 0.5)
        XCTAssertEqual(player.duration, 1, accuracy: 0.01)
        await wait(0.3)
        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(player.currentTime, 0.6, "time is measured in the new file")
        await wait(1.2)
        XCTAssertTrue(finished, "only the incoming file reports finishing")
    }
}
