import Foundation

struct RemoteSearchResult: Identifiable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let source: String
    let downloadURL: URL?
    let artworkURL: URL?
    let isLocal: Bool
}

protocol RemoteMusicSource {
    func search(_ query: String) async throws -> [RemoteSearchResult]
}

struct FeedItem: Codable {
    let id: String?
    let title: String
    let artist: String?
    let album: String?
    let url: String
    let artworkURL: String?
    let fileType: String?
}

final class JSONFeedRemoteMusicSource: RemoteMusicSource {
    private let feedURLs: [URL]

    init(feedURLs: [URL]) {
        self.feedURLs = feedURLs
    }

    func search(_ query: String) async throws -> [RemoteSearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [RemoteSearchResult] = []
        for feedURL in feedURLs {
            let data = try await fetchFeedData(from: feedURL)
            let feedItems = try decodeFeed(data)
            let normalizedQuery = query.lowercased()
            let matches = feedItems.filter { item in
                let haystack = [item.title, item.artist ?? "", item.album ?? ""].joined(separator: " ").lowercased()
                return haystack.contains(normalizedQuery)
            }
            for item in matches {
                let resolvedURL = URL(string: item.url)
                if resolvedURL != nil {
                    results.append(
                        RemoteSearchResult(
                            id: UUID(),
                            title: item.title,
                            artist: item.artist ?? "Unknown Artist",
                            album: item.album ?? "Unknown Album",
                            source: feedURL.host ?? "feed",
                            downloadURL: resolvedURL,
                            artworkURL: URL(string: item.artworkURL ?? ""),
                            isLocal: false
                        )
                    )
                }
            }
        }
        return results
    }

    private func fetchFeedData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func decodeFeed(_ data: Data) throws -> [FeedItem] {
        let decoder = JSONDecoder()
        return try decoder.decode([FeedItem].self, from: data)
    }
}
