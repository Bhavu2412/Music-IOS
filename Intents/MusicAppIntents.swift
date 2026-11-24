import AppIntents
import Foundation

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or pause"
    static var description: LocalizedStringResource = "Toggle the current playback state."

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackService.shared.togglePlayback()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next track"
    static var description: LocalizedStringResource = "Skip to the next audio item."

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackService.shared.next()
        return .result()
    }
}

struct ShuffleLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle shuffle"
    static var description: LocalizedStringResource = "Turn shuffle on or off for the current queue."

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackService.shared.toggleShuffle()
        return .result()
    }
}
