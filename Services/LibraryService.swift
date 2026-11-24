import AVFoundation
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum LibraryError: LocalizedError {
    case unsupportedFile(String)
    case couldNotCreateBookmark(String)
    case fileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            "“\(name)” is not a supported audio file."
        case .couldNotCreateBookmark(let name):
            "Music could not save access to “\(name)”. Try importing it again."
        case .fileUnavailable(let name):
            "“\(name)” is no longer available. Re-import the file from Files."
        }
    }
}

@MainActor
protocol LibraryServicing {
    func importItems(_ urls: [URL], into context: ModelContext) async throws -> [Track]
    func resolveURL(for track: Track) throws -> URL
}

@MainActor
final class LibraryService: LibraryServicing {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "alac"]

    func importItems(_ urls: [URL], into context: ModelContext) async throws -> [Track] {
        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        let files = try collectAudioFiles(from: urls)
        guard !files.isEmpty else {
            throw LibraryError.unsupportedFile(urls.first?.lastPathComponent ?? "selection")
        }

        var imported: [Track] = []
        for file in files {
            let track = try await importFile(file, into: context)
            imported.append(track)
            try updateAlbum(for: track, in: context)
        }
        try context.save()
        return imported
    }

    func resolveURL(for track: Track) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: track.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LibraryError.fileUnavailable(track.originalFilename)
            }
            if isStale {
                track.bookmarkData = try makeBookmark(for: url)
            }
            return url
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.fileUnavailable(track.originalFilename)
        }
    }

    private func collectAudioFiles(from urls: [URL]) throws -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let child as URL in enumerator where Self.isSupported(child) {
                    files.append(child)
                }
            } else if Self.isSupported(url) {
                files.append(url)
            }
        }
        return files
    }

    private func updateAlbum(for track: Track, in context: ModelContext) throws {
        let albums = try context.fetch(FetchDescriptor<Album>())
        if let album = albums.first(where: { $0.title == track.albumTitle && $0.artist == track.artist }) {
            if !album.trackIDs.contains(track.id) { album.trackIDs.append(track.id) }
            if album.artworkData == nil { album.artworkData = track.artworkData }
        } else {
            context.insert(Album(
                title: track.albumTitle,
                artist: track.artist,
                artworkData: track.artworkData,
                trackIDs: [track.id]
            ))
        }
    }

    private func importFile(_ url: URL, into context: ModelContext) async throws -> Track {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        let bookmark: Data
        do {
            bookmark = try makeBookmark(for: url)
        } catch {
            throw LibraryError.couldNotCreateBookmark(url.lastPathComponent)
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let metadata = try await asset.load(.commonMetadata)

        let title = await stringValue(in: metadata, key: .commonKeyTitle)
            .flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        let artist = await stringValue(in: metadata, key: .commonKeyArtist) ?? "Unknown Artist"
        let album = await stringValue(in: metadata, key: .commonKeyAlbumName) ?? "Unknown Album"
        let artwork = await artworkValue(in: metadata)
        let seconds = CMTimeGetSeconds(duration)

        let track = Track(
            title: title,
            artist: artist,
            albumTitle: album,
            duration: seconds.isFinite ? max(seconds, 0) : 0,
            artworkData: artwork,
            bookmarkData: bookmark,
            originalFilename: url.lastPathComponent
        )
        context.insert(track)
        return track
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func stringValue(in metadata: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.stringValue)
    }

    private func artworkValue(in metadata: [AVMetadataItem]) async -> Data? {
        guard let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }) else { return nil }
        return try? await item.load(.dataValue)
    }

    private static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
