import Foundation

@MainActor
@Observable
final class SearchService {
    var query = ""
    var recentSearches: [String] = []
    var localResults: [Track] = []
    var onlineResults: [RemoteSearchResult] = []
    var isSearching = false
    var errorMessage: String?
    var offlineBannerVisible = false

    private let connectivity: ConnectivityService
    private let remoteSource: any RemoteMusicSource
    private let libraryTracks: [Track]

    init(libraryTracks: [Track], connectivity: ConnectivityService, remoteSource: some RemoteMusicSource) {
        self.libraryTracks = libraryTracks
        self.connectivity = connectivity
        self.remoteSource = remoteSource
        if let strings = UserDefaults.standard.stringArray(forKey: "music.recentSearches") {
            self.recentSearches = strings
        } else if let raw = UserDefaults.standard.string(forKey: "music.recentSearches"),
                  let data = raw.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data) {
            self.recentSearches = strings
        } else {
            self.recentSearches = []
        }
    }

    convenience init(libraryTracks: [Track]) {
        self.init(libraryTracks: libraryTracks, connectivity: ConnectivityService(), remoteSource: JSONFeedRemoteMusicSource(feedURLs: []))
    }

    func performSearch(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            localResults = []
            onlineResults = []
            return
        }

        isSearching = true
        errorMessage = nil
        offlineBannerVisible = !connectivity.isOnline

        localResults = libraryTracks.filter { track in
            let searchable = [track.title, track.artist, track.albumTitle, track.originalFilename].joined(separator: " ").lowercased()
            return searchable.contains(trimmed.lowercased())
        }

        if !connectivity.isOnline {
            isSearching = false
            saveRecentSearch(trimmed)
            return
        }

        do {
            let online = try await remoteSource.search(trimmed)
            onlineResults = online
            saveRecentSearch(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            onlineResults = []
        }

        isSearching = false
    }

    private func saveRecentSearch(_ search: String) {
        var searches = recentSearches.filter { $0.lowercased() != search.lowercased() }
        searches.insert(search, at: 0)
        recentSearches = Array(searches.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: "music.recentSearches")
    }
}
