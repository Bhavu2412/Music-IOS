import AppIntents
import Foundation

// Shared by the app and the widget extension. As AudioPlaybackIntents they always run in
// the app's process (launched in the background if needed), so widget and Control Center
// buttons drive the real player. The widget's copy never calls into the player.

struct PlayPauseIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback of the current song.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await PlaybackIntentRunner.run { $0.togglePlayback() }
        #endif
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Song"
    static var description = IntentDescription("Skips to the next song in the queue.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await PlaybackIntentRunner.run { $0.next() }
        #endif
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Song"
    static var description = IntentDescription("Goes back to the previous song, or the start of this one.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await PlaybackIntentRunner.run { $0.previous() }
        #endif
        return .result()
    }
}
