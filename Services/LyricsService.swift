import AVFoundation
import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum Lyrics: Equatable {
    case synced([LyricLine])
    case plain(String)
}

/// Finds lyrics for a track: text saved on the track (pasted in Edit Info), a matching .lrc file
/// next to the audio file, or lyrics embedded in the file's tags. LRC text is shown synced.
@MainActor
enum LyricsService {
    static func lyrics(for track: Track) async -> Lyrics? {
        if let saved = track.lyrics, let parsed = parse(saved) { return parsed }
        guard let url = try? LibraryService().resolveURL(for: track) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let base = url.deletingPathExtension()
        for candidate in [base.appendingPathExtension("lrc"), URL(fileURLWithPath: base.path + "-lyrics.lrc")] {
            if let text = try? String(contentsOf: candidate, encoding: .utf8), let parsed = parse(text) {
                return parsed
            }
        }
        if let embedded = try? await AVURLAsset(url: url).load(.lyrics), let parsed = parse(embedded) {
            return parsed
        }
        return nil
    }

    /// LRC ("[mm:ss.xx] line", several stamps per line allowed) → synced; other text → plain.
    static func parse(_ text: String) -> Lyrics? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/
        var lines: [(TimeInterval, String)] = []
        for raw in trimmed.components(separatedBy: .newlines) {
            let matches = raw.matches(of: stamp)
            guard let last = matches.last else { continue }
            let lyric = raw[last.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(match.output.1) ?? 0
                let seconds = Double(match.output.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                lines.append((minutes * 60 + seconds, lyric))
            }
        }
        if lines.isEmpty { return .plain(trimmed) }
        let sorted = lines.sorted { $0.0 < $1.0 }
        return .synced(sorted.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) })
    }
}
