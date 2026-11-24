import SwiftUI

enum AppIcon {
    case library
    case search
    case playlists
    case settings
    case songs
    case albums
    case artists
    case favorite
    case add
    case more
    case play
    case pause
    case next
    case previous
    case skipBack
    case skipForward
    case shuffle
    case repeatAll
    case repeatOne
    case queue
    case airPlay
    case lyrics
    case dismiss
    case playNext
    case addQueue
    case addToPlaylist
    case createPlaylist
    case merge
    case share
    case delete
    case files
    case url
    case download
    case paste
    case success
    case error
    case offline
    case recent
    case clear
    case chevron
    case equalizer
    case playbackSpeed
    case crossfade
    case gapless
    case remoteFeeds
    case sleepTimer
    case storage
    case iCloud
    case waveform
    case playbackModeNormal
    case checkmark
    case unselected
    case remove
    case textSize
    case haptics

    func symbolName(active: Bool = false) -> String {
        switch self {
        case .library: active ? "books.vertical.fill" : "books.vertical"
        case .search: "magnifyingglass"
        case .playlists: "music.note.list"
        case .settings: active ? "gearshape.fill" : "gearshape"
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .favorite: active ? "heart.fill" : "heart"
        case .add: "plus"
        case .more: "ellipsis"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .skipBack: "gobackward.15"
        case .skipForward: "goforward.15"
        case .shuffle: "shuffle"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .queue: "list.bullet"
        case .airPlay: "airplayaudio"
        case .lyrics: "quote.bubble"
        case .dismiss: "chevron.down"
        case .playNext: "text.line.first.and.arrowtriangle.forward"
        case .addQueue: "text.append"
        case .addToPlaylist: "text.badge.plus"
        case .createPlaylist: "plus.rectangle.on.folder"
        case .merge: "arrow.triangle.merge"
        case .share: "square.and.arrow.up"
        case .delete: "trash"
        case .files: "folder"
        case .url: "link"
        case .download: "arrow.down.circle"
        case .paste: "doc.on.clipboard"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .offline: "wifi.slash"
        case .recent: "clock.arrow.circlepath"
        case .clear: "xmark.circle.fill"
        case .chevron: "chevron.right"
        case .equalizer: "slider.vertical.3"
        case .playbackSpeed: "gauge.with.dots.needle.67percent"
        case .crossfade: "waveform.path"
        case .gapless: "infinity"
        case .remoteFeeds: "antenna.radiowaves.left.and.right"
        case .sleepTimer: "moon.zzz"
        case .storage: "internaldrive"
        case .iCloud: "icloud"
        case .waveform: "waveform"
        case .playbackModeNormal: "arrow.right"
        case .checkmark: "checkmark"
        case .unselected: "circle"
        case .remove: "minus"
        case .textSize: "textformat.size"
        case .haptics: "hand.tap"
        }
    }
}

enum AppIconSize {
    case row
    case tab
    case toolbar
    case playerSecondary
    case skip
    case transport
    case playPause
    case artworkPlaceholder
    case emptyState

    var points: CGFloat {
        switch self {
        case .row: 20
        case .tab, .toolbar: 24
        case .playerSecondary: 28
        case .skip: 36
        case .transport: 44
        case .playPause: 72
        case .artworkPlaceholder: 40
        case .emptyState: 64
        }
    }
}

struct AppIconView: View {
    let icon: AppIcon
    var size: AppIconSize = .row
    var weight: Font.Weight = .regular
    var isActive = false
    var color: Color = .secondary

    var body: some View {
        Image(systemName: icon.symbolName(active: isActive))
            .font(.system(size: size.points, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
