import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var albumTitle: String
    var duration: Double
    var artworkData: Data?
    var bookmarkData: Data
    var originalFilename: String
    var bitrate: Double?
    var isFavorite: Bool
    var playCount: Int
    var dateAdded: Date
    var sourceURL: String?
    var isDownloaded: Bool
    var isAvailableOffline: Bool
    var remoteURLString: String?
    var lastPlayedAt: Date?
    /// Lyrics entered by the user (plain text or LRC).
    var lyrics: String?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Unknown Artist",
        albumTitle: String = "Unknown Album",
        duration: Double = 0,
        artworkData: Data? = nil,
        bookmarkData: Data,
        originalFilename: String,
        bitrate: Double? = nil,
        isFavorite: Bool = false,
        playCount: Int = 0,
        dateAdded: Date = .now,
        sourceURL: String? = nil,
        isDownloaded: Bool = false,
        isAvailableOffline: Bool = true,
        remoteURLString: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.artworkData = artworkData
        self.bookmarkData = bookmarkData
        self.originalFilename = originalFilename
        self.bitrate = bitrate
        self.isFavorite = isFavorite
        self.playCount = playCount
        self.dateAdded = dateAdded
        self.sourceURL = sourceURL
        self.isDownloaded = isDownloaded
        self.isAvailableOffline = isAvailableOffline
        self.remoteURLString = remoteURLString
    }
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var trackIDsData: Data

    var trackIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: trackIDsData)) ?? [] }
        set { trackIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.trackIDsData = (try? JSONEncoder().encode(trackIDs)) ?? Data()
    }
}

@Model
final class Album {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var artworkData: Data?
    var trackIDsData: Data

    var trackIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: trackIDsData)) ?? [] }
        set { trackIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        artworkData: Data? = nil,
        trackIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.trackIDsData = (try? JSONEncoder().encode(trackIDs)) ?? Data()
    }
}

enum QueueRepeatMode: String, Codable, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }
}

struct QueueState: Codable {
    var trackIDs: [UUID] = []
    var currentTrackID: UUID?
    var position: Double = 0
    var isShuffled = false
    var repeatMode: QueueRepeatMode = .off
}
