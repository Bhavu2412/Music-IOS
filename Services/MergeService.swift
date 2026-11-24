import AVFoundation
import Foundation
import SwiftData

@MainActor
protocol MergeServicing {
    func detectDuplicateTracks(in tracks: [Track]) -> [(Track, Track)]
    func mergeDuplicateTracks(_ duplicates: [(Track, Track)], in context: ModelContext) throws
    func mergePlaylists(_ playlists: [Playlist], into name: String, in context: ModelContext) throws -> Playlist
    func exportMergedAudio(from tracks: [Track], crossfade: Double, outputName: String) async throws -> URL
}

@MainActor
final class MergeService: MergeServicing {
    func detectDuplicateTracks(in tracks: [Track]) -> [(Track, Track)] {
        var matches: [(Track, Track)] = []
        for i in 0..<tracks.count {
            for j in (i + 1)..<tracks.count {
                let a = tracks[i]
                let b = tracks[j]
                guard a.id != b.id else { continue }
                let sameTitle = normalized(a.title) == normalized(b.title)
                let sameArtist = normalized(a.artist) == normalized(b.artist)
                let sameDuration = abs(a.duration - b.duration) <= 2.0
                if sameTitle && sameArtist && sameDuration {
                    matches.append((a, b))
                }
            }
        }
        return matches
    }

    func mergeDuplicateTracks(_ duplicates: [(Track, Track)], in context: ModelContext) throws {
        for (primary, secondary) in duplicates {
            let primaryBitrate = primary.bitrate ?? 0
            let secondaryBitrate = secondary.bitrate ?? 0
            let winner = primaryBitrate >= secondaryBitrate ? primary : secondary
            let loser = winner.id == primary.id ? secondary : primary
            winner.title = winner.title.isEmpty ? loser.title : winner.title
            winner.artist = winner.artist == "Unknown Artist" && loser.artist != "Unknown Artist" ? loser.artist : winner.artist
            winner.albumTitle = winner.albumTitle == "Unknown Album" && loser.albumTitle != "Unknown Album" ? loser.albumTitle : winner.albumTitle
            winner.artworkData = winner.artworkData ?? loser.artworkData
            winner.playCount += loser.playCount
            winner.isFavorite = winner.isFavorite || loser.isFavorite
            context.delete(loser)
        }
        try context.save()
    }

    func mergePlaylists(_ playlists: [Playlist], into name: String, in context: ModelContext) throws -> Playlist {
        var mergedIDs: [UUID] = []
        var seen = Set<UUID>()
        for playlist in playlists {
            for id in playlist.trackIDs where !seen.contains(id) {
                mergedIDs.append(id)
                seen.insert(id)
            }
        }
        let merged = Playlist(name: name, trackIDs: mergedIDs)
        context.insert(merged)
        try context.save()
        return merged
    }

    func exportMergedAudio(from tracks: [Track], crossfade: Double, outputName: String) async throws -> URL {
        guard tracks.count >= 2 else { throw AudioMergeError.requiresMultipleTracks }

        let composition = AVMutableComposition()
        var segments: [(track: AVMutableCompositionTrack, sourceRange: CMTimeRange, source: AVAssetTrack)] = []
        var audioMixParameters: [AVAudioMixInputParameters] = []

        for track in tracks {
            let url = try resolve(track: track)
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let sourceRange = try await sourceTrack.load(.timeRange)
            let duration = sourceRange.duration
            guard duration.seconds.isFinite, duration.seconds > 0 else { continue }
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw AudioMergeError.couldNotCreateComposition
            }
            segments.append((compositionTrack, sourceRange, sourceTrack))
        }

        guard segments.count >= 2 else { throw AudioMergeError.requiresMultipleTracks }

        let requestedCrossfade = max(0, min(crossfade, 10))
        let overlaps = zip(segments, segments.dropFirst()).map { pair in
            let previousDuration = max(pair.0.sourceRange.duration.seconds / 2, 0)
            let nextDuration = max(pair.1.sourceRange.duration.seconds / 2, 0)
            return min(requestedCrossfade, min(previousDuration, nextDuration))
        }

        var cursor: CMTime = .zero
        for (index, segment) in segments.enumerated() {
            let startOverlap = index > 0 ? overlaps[index - 1] : 0
            let endOverlap = index < overlaps.count ? overlaps[index] : 0
            try segment.track.insertTimeRange(
                segment.sourceRange,
                of: segment.source,
                at: cursor
            )
            let parameters = AVMutableAudioMixInputParameters(track: segment.track)
            parameters.setVolume(startOverlap > 0 ? 0 : 1, at: cursor)

            if startOverlap > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: 1,
                    timeRange: CMTimeRange(
                        start: cursor,
                        duration: CMTime(seconds: startOverlap, preferredTimescale: 600)
                    )
                )
            }
            if endOverlap > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: 1,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: CMTimeAdd(
                            cursor,
                            CMTime(seconds: segment.sourceRange.duration.seconds - endOverlap, preferredTimescale: 600)
                        ),
                        duration: CMTime(seconds: endOverlap, preferredTimescale: 600)
                    )
                )
            }
            audioMixParameters.append(parameters)

            cursor = CMTimeAdd(cursor, segment.sourceRange.duration)
            if endOverlap > 0 {
                cursor = CMTimeSubtract(cursor, CMTime(seconds: endOverlap, preferredTimescale: 600))
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParameters
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeName = outputName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        var outputURL = documents.appendingPathComponent("\(safeName).m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = documents.appendingPathComponent("\(safeName) \(UUID().uuidString.prefix(8)).m4a")
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioMergeError.couldNotCreateExporter
        }
        session.outputFileType = .m4a
        session.outputURL = outputURL
        session.audioMix = audioMix
        nonisolated(unsafe) let exportSession = session
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: exportSession.error ?? AudioMergeError.exportFailed)
                }
            }
        }

        return outputURL
    }

    private func normalizeTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum AudioMergeError: LocalizedError {
        case requiresMultipleTracks
        case couldNotCreateComposition
        case couldNotCreateExporter
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .requiresMultipleTracks:
                "Select at least two playable audio tracks to merge."
            case .couldNotCreateComposition:
                "The audio composition could not be created."
            case .couldNotCreateExporter:
                "The audio export service could not be started."
            case .exportFailed:
                "The merged audio could not be exported."
            }
        }
    }

    private func normalized(_ value: String) -> String {
        normalizeTitle(value)
    }

    private func resolve(track: Track) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: track.bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryError.fileUnavailable(track.originalFilename)
        }
        return url
    }
}
