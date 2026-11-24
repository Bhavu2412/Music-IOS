import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: UUID
    let time: TimeInterval
    let text: String
}

@MainActor
protocol LyricsServicing {
    func loadLyrics(for track: Track) async throws -> [LyricLine]
}

@MainActor
final class LyricsService: LyricsServicing {
    func loadLyrics(for track: Track) async throws -> [LyricLine] {
        let fileManager = FileManager.default
        let trackURL = try LibraryService().resolveURL(for: track)
        let directory = trackURL.deletingLastPathComponent()
        let candidates = [
            directory.appendingPathComponent(trackURL.deletingPathExtension().lastPathComponent + ".lrc"),
            directory.appendingPathComponent((trackURL.deletingPathExtension().lastPathComponent + "-lyrics") + ".lrc")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            let data = try Data(contentsOf: candidate)
            return parseLRC(data)
        }

        if let lyrics = track.title.components(separatedBy: "[").first, lyrics.isEmpty == false {
            return []
        }

        return []
    }

    private func parseLRC(_ data: Data) -> [LyricLine] {
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: .newlines)
        let timestampPattern = try? NSRegularExpression(
            pattern: #"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$"#
        )
        var parsed: [LyricLine] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let timestampPattern,
                let match = timestampPattern.firstMatch(
                    in: trimmed,
                    range: NSRange(trimmed.startIndex..., in: trimmed)
                ),
                let minuteRange = Range(match.range(at: 1), in: trimmed),
                let secondRange = Range(match.range(at: 2), in: trimmed),
                let lyricRange = Range(match.range(at: 3), in: trimmed),
                let minute = Double(trimmed[minuteRange]),
                let second = Double(trimmed[secondRange])
            else {
                continue
            }
            parsed.append(
                LyricLine(
                    id: UUID(),
                    time: minute * 60 + second,
                    text: String(trimmed[lyricRange])
                )
            )
        }
        return parsed.sorted { $0.time < $1.time }
    }
}
