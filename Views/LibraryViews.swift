import SwiftData
import SwiftUI
import UIKit

enum LibraryTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case search = "Search"
    case playlists = "Playlists"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: AppIcon {
        switch self {
        case .library: .library
        case .search: .search
        case .playlists: .playlists
        case .settings: .settings
        }
    }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case favorites = "Favorites"

    var id: String { rawValue }

    var icon: AppIcon {
        switch self {
        case .songs: .songs
        case .albums: .albums
        case .artists: .artists
        case .favorites: .favorite
        }
    }
}

struct LibraryTabsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var playback = PlaybackService.shared
    @State private var connectivity = ConnectivityService()
    @State private var selectedTab: LibraryTab = .library
    @State private var selectedLibrarySection: LibrarySection = .songs
    @State private var showingPicker = false
    @State private var showingCreatePlaylist = false
    @State private var showingURLImport = false
    @State private var showingMergeDuplicates = false
    @State private var showingPlaylistMerge = false
    @State private var showingAudioMerge = false
    @State private var showingNowPlaying = false
    @State private var restoredPlayback = false
    @State private var duplicatePairs: [(Track, Track)] = []
    @State private var selectedPlaylistIDs: [UUID] = []
    @State private var selectedMergeTracks: [Track] = []
    @State private var shouldPresentMergeAfterPlayerDismissal = false

    var body: some View {
        ZStack {
            AnimatedArtworkBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NavigationStack {
                    tabContent
                        .navigationTitle(selectedTab.rawValue)
                        .navigationBarTitleDisplayMode(.large)
                        .toolbarBackground(DesignSystem.AppColors.background, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbar {
                            if selectedTab == .library {
                                ToolbarItemGroup(placement: .topBarTrailing) {
                                    Button {
                                        selectedTab = .search
                                    } label: {
                                        AppIconView(icon: .search, size: .toolbar)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Search library")

                                    importMenu
                                }
                            }
                            if selectedTab == .playlists {
                                ToolbarItem(placement: .topBarTrailing) {
                                    importMenu
                                }
                            }
                        }
                }
                // Fresh stack per tab, so a pushed album page doesn't linger on other tabs.
                .id(selectedTab)

                if playback.currentTrack != nil {
                    MiniPlayer(playback: playback) {
                        presentNowPlaying()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                DesignSystem.GlassTabBar(selection: $selectedTab)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .tint(DesignSystem.AppColors.accent)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(
                onPick: { urls in
                    showingPicker = false
                    Task { await viewModel.importItems(urls, into: modelContext) }
                },
                onCancel: { showingPicker = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingURLImport) {
            URLImportView()
        }
        .sheet(isPresented: $showingMergeDuplicates) {
            MergeDuplicatesView(duplicates: duplicatePairs, onMerge: {
                do {
                    let deleted = try MergeService().mergeDuplicateTracks(duplicatePairs, in: modelContext)
                    playback.remove(trackIDs: deleted)
                    viewModel.errorMessage = "Merged \(deleted.count) duplicate \(deleted.count == 1 ? "song" : "songs")."
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
                showingMergeDuplicates = false
            }, onCancel: {
                showingMergeDuplicates = false
            })
        }
        .sheet(isPresented: $showingPlaylistMerge) {
            PlaylistMergeView(playlists: playlists, initiallySelected: Set(selectedPlaylistIDs), onMerge: { name, selected in
                do {
                    _ = try MergeService().mergePlaylists(playlists.filter { selected.contains($0.id) }, into: name, in: modelContext)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
                showingPlaylistMerge = false
            })
        }
        .sheet(isPresented: $showingAudioMerge) {
            AudioMergeView(
                tracks: tracks,
                initiallySelectedTrackIDs: Set(
                    (selectedMergeTracks.isEmpty ? tracks : selectedMergeTracks).map(\.id)
                ),
                onComplete: { url in
                if let url {
                    Task {
                        do {
                            _ = try await LibraryService().importItems([url], into: modelContext)
                            viewModel.errorMessage = "Merged audio added to your library."
                        } catch {
                            viewModel.errorMessage = "The merged file was exported, but could not be added to your library: \(error.localizedDescription)"
                        }
                    }
                }
                showingAudioMerge = false
            })
        }
        .fullScreenCover(isPresented: $showingNowPlaying, onDismiss: {
            guard shouldPresentMergeAfterPlayerDismissal else { return }
            shouldPresentMergeAfterPlayerDismissal = false
            showingAudioMerge = true
        }) {
            NowPlayingView(
                playback: playback,
                isOnline: connectivity.isOnline,
                playlists: playlists,
                context: modelContext,
                openSettings: {
                    showingNowPlaying = false
                    selectedTab = .settings
                },
                mergeTrack: { track in
                    selectedMergeTracks = [track]
                    shouldPresentMergeAfterPlayerDismissal = true
                    showingNowPlaying = false
                }
            )
        }
        .alert("Music", isPresented: Binding(
            get: { viewModel.errorMessage != nil || playback.errorMessage != nil },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    playback.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                playback.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? playback.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if !connectivity.isOnline {
                HStack(spacing: 8) {
                    AppIconView(icon: .offline)
                    Text("Offline: showing library only")
                        .font(DesignSystem.caption)
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .glassCapsule()
                    .padding(.top, 8)
            }
        }
        .overlay {
            if viewModel.isImporting {
                ProgressView("Importing audio…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task {
            restorePlaybackIfReady()
            await importDocumentsIfAny()
        }
        .onChange(of: tracks.count) {
            restorePlaybackIfReady()
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            CreatePlaylistSheet { name in
                modelContext.insert(Playlist(name: name))
                do { try modelContext.save() }
                catch { viewModel.errorMessage = error.localizedDescription }
            }
            .presentationCornerRadius(28)
        }
    }

    private var importMenu: some View {
        Menu {
            Button {
                showingPicker = true
            } label: {
                Label("Import from Files", systemImage: AppIcon.files.symbolName())
            }
            Button {
                showingURLImport = true
            } label: {
                Label("Import from URL", systemImage: AppIcon.url.symbolName())
            }
            .disabled(!connectivity.isOnline)
            Button {
                duplicatePairs = MergeService().detectDuplicateTracks(in: tracks)
                if duplicatePairs.isEmpty {
                    viewModel.errorMessage = "No duplicate songs found."
                } else {
                    showingMergeDuplicates = true
                }
            } label: {
                Label("Check duplicates", systemImage: AppIcon.paste.symbolName())
            }
            Button {
                selectedPlaylistIDs = Array(playlists.prefix(2)).map(\.id)
                showingPlaylistMerge = true
            } label: {
                Label("Merge playlists", systemImage: AppIcon.merge.symbolName())
            }
            .disabled(playlists.count < 2)
            Button {
                showingAudioMerge = true
            } label: {
                Label("Merge selected audio", systemImage: AppIcon.merge.symbolName())
            }
        } label: {
            AppIconView(icon: .add, size: .toolbar, weight: .semibold, color: DesignSystem.AppColors.accent)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Import and library actions")
    }

    private func restorePlaybackIfReady() {
        guard !restoredPlayback, !tracks.isEmpty else { return }
        restoredPlayback = true
        playback.resume(from: tracks)
    }

    private func importDocumentsIfAny() async {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) else { return }
        let audioExtensions = LibraryService.supportedExtensions
        let pending = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        let existingFilenames = Set(tracks.map(\.originalFilename))
        let newFiles = pending.filter { !existingFilenames.contains($0.lastPathComponent) }
        guard !newFiles.isEmpty else { return }
        await viewModel.importItems(newFiles, into: modelContext)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .library:
            libraryContent
        case .search:
            SearchLibraryView(
                tracks: tracks,
                playlists: playlists,
                playback: playback,
                isOnline: connectivity.isOnline,
                onImportFiles: { showingPicker = true },
                onImportURL: { showingURLImport = true },
                onTrackSelected: { presentNowPlaying() },
                onCancel: { selectedTab = .library }
            )
        case .playlists:
            PlaylistList(
                tracks: tracks,
                playlists: playlists,
                playback: playback,
                context: modelContext,
                reportError: { viewModel.errorMessage = $0 },
                onTrackSelected: { presentNowPlaying() },
                onCreatePlaylist: { showingCreatePlaylist = true }
            )
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        VStack(spacing: 0) {
            DesignSystem.LibrarySectionPicker(selection: $selectedLibrarySection)
            Group {
                switch selectedLibrarySection {
                case .songs:
                    trackList(tracks, showsDaypartGreeting: true)
                case .albums:
                    AlbumList(
                        tracks: tracks,
                        playback: playback,
                        onImportFiles: { showingPicker = true },
                        onTrackSelected: { presentNowPlaying() }
                    )
                case .artists:
                    ArtistList(
                        tracks: tracks,
                        playback: playback,
                        onImportFiles: { showingPicker = true },
                        onTrackSelected: { presentNowPlaying() }
                    )
                case .favorites:
                    trackList(
                        tracks.filter(\.isFavorite),
                        emptyState: .favorites,
                        showsFavoritesHeader: true
                    )
                }
            }
        }
    }

    private func trackList(
        _ items: [Track],
        showsDaypartGreeting: Bool = false,
        emptyState: TrackListEmptyState = .library,
        showsFavoritesHeader: Bool = false
    ) -> some View {
        TrackList(
            tracks: items,
            playlists: playlists,
            playback: playback,
            context: modelContext,
            isOnline: connectivity.isOnline,
            showsDaypartGreeting: showsDaypartGreeting,
            emptyState: emptyState,
            showsFavoritesHeader: showsFavoritesHeader,
            onImportFiles: { showingPicker = true },
            onImportURL: { showingURLImport = true },
            reportError: { viewModel.errorMessage = $0 },
            onTrackSelected: { presentNowPlaying() },
            onBrowseLibrary: {
                selectedTab = .library
                selectedLibrarySection = .songs
            },
            onOpenSettings: { selectedTab = .settings }
        )
    }

    private func presentNowPlaying() {
        withAnimation(DesignSystem.Motion.spring) {
            showingNowPlaying = true
        }
    }
}

private struct SearchLibraryView: View {
    let tracks: [Track]
    let playlists: [Playlist]
    @ObservedObject var playback: PlaybackService
    let isOnline: Bool
    let onImportFiles: () -> Void
    let onImportURL: () -> Void
    let onTrackSelected: () -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @State private var selectedFilter: SearchFilter = .all
    @State private var onlineResults: [RemoteSearchResult] = []
    @State private var isSearchingOnline = false
    @State private var onlineError: String?
    @State private var onlineSearchTask: Task<Void, Never>?
    @State private var downloadingIDs = Set<UUID>()
    @State private var downloadedIDs = Set<UUID>()
    @Environment(\.modelContext) private var modelContext
    @AppStorage("music.feedURLs") private var feedURLs: [String] = []
    @AppStorage("music.recentSearches") private var recentSearches: [String] = []
    @FocusState private var searchFocused: Bool

    private var matchingTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return tracks.filter { track in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all, .songs: matchesFilter = true
            case .albums: matchesFilter = track.albumTitle.localizedCaseInsensitiveContains(query)
            case .artists: matchesFilter = track.artist.localizedCaseInsensitiveContains(query)
            case .playlists: matchesFilter = false
            }
            guard matchesFilter else { return false }
            return [track.title, track.artist, track.albumTitle, track.originalFilename]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var hasQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                DesignSystem.GlassSearchBar(
                    text: $searchText,
                    placeholder: "Search songs, artists, albums",
                    focus: $searchFocused
                )
                Button("Cancel", action: onCancel)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(DesignSystem.AppColors.accent)
                    .frame(minHeight: 44)
                    .fixedSize()
                    .accessibilityLabel("Cancel search")
            }
            .padding(.horizontal, DesignSystem.AppSpacing.screen)
            .padding(.top, 12)

            if !isOnline {
                HStack(spacing: 8) {
                    AppIconView(icon: .offline)
                    Text("Offline - showing your library only")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .glassCapsule()
                .padding(.horizontal, DesignSystem.AppSpacing.screen)
            }

            filterChips

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !hasQuery {
                        recentSearchesView
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            DesignSystem.SectionHeader(title: "On this device")
                            if selectedFilter == .playlists {
                                playlistSearchResults
                            } else if matchingTracks.isEmpty {
                                DesignSystem.EmptyStateView(
                                    title: "No search results",
                                    message: "Try another title, artist, or album.",
                                    icon: .search,
                                    actionTitle: "Clear Search",
                                    actionIcon: .clear,
                                    action: { searchText = "" }
                                )
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(matchingTracks) { track in
                                        SearchTrackRow(
                                            track: track,
                                            isCurrent: playback.currentTrack?.id == track.id,
                                            isPlaying: playback.isPlaying,
                                            isOffline: !isOnline,
                                            select: {
                                                playback.play(track, from: matchingTracks)
                                                onTrackSelected()
                                            },
                                            playNext: { playback.playNext(track) },
                                            addToQueue: { playback.addToQueue(track) },
                                            searchText: searchText
                                        )
                                    }
                                }
                                .padding(8)
                                .glassCard(cornerRadius: 20)
                                .padding(.horizontal, 14)
                            }
                        }

                        if isOnline && selectedFilter != .playlists {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    DesignSystem.SectionHeader(title: "Online")
                                    if isSearchingOnline {
                                        ProgressView().tint(DesignSystem.AppColors.accent)
                                    }
                                }
                                if !onlineResults.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(onlineResults) { result in
                                            Button { download(result) } label: {
                                            HStack(spacing: 12) {
                                                DesignSystem.ArtworkView(
                                                    data: nil,
                                                    size: 52,
                                                    placeholderKey: result.album
                                                )
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(result.title)
                                                        .font(.system(.headline, design: .rounded))
                                                        .lineLimit(1)
                                                    Text("\(result.artist) · \(result.source)")
                                                        .font(.system(.subheadline, design: .rounded))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 0)
                                                if downloadingIDs.contains(result.id) {
                                                    ProgressView().tint(DesignSystem.AppColors.accent)
                                                } else {
                                                    AppIconView(icon: downloadedIDs.contains(result.id) ? .success : .download, size: .row)
                                                }
                                            }
                                            .frame(minHeight: 68)
                                            .padding(.horizontal, 12)
                                            .contentShape(Rectangle())
                                            }
                                            .buttonStyle(DesignSystem.PremiumPressStyle())
                                            .disabled(result.downloadURL == nil || downloadingIDs.contains(result.id) || downloadedIDs.contains(result.id))
                                            .accessibilityLabel("Download \(result.title) by \(result.artist)")
                                        }
                                    }
                                    .glassCard(cornerRadius: 20)
                                    .padding(.horizontal, 14)
                                } else if isSearchingOnline {
                                    DesignSystem.LoadingRowsView()
                                        .padding(8)
                                        .glassCard(cornerRadius: 20)
                                        .padding(.horizontal, 14)
                                } else if let onlineError {
                                    Text(onlineError)
                                        .font(DesignSystem.subhead)
                                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                        .padding(DesignSystem.AppSpacing.s16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassCard(cornerRadius: 20)
                                        .padding(.horizontal, 14)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 110)
                .animation(DesignSystem.Motion.spring, value: hasQuery)
            }
            .scrollIndicators(.hidden)
        }
        .background(DesignSystem.AppColors.background)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: searchText) {
            scheduleOnlineSearch()
        }
        .onChange(of: isOnline) {
            scheduleOnlineSearch()
        }
        .onDisappear {
            onlineSearchTask?.cancel()
            isSearchingOnline = false
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.subhead.weight(.semibold))
                            .foregroundStyle(selectedFilter == filter ? DesignSystem.AppColors.accentContrastText : DesignSystem.AppColors.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background {
                                if selectedFilter == filter {
                                    Capsule().fill(DesignSystem.AppColors.accent).frame(height: 36)
                                } else {
                                    Capsule().fill(DesignSystem.AppColors.card).frame(height: 36)
                                }
                            }
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                }
            }
            .padding(.horizontal, DesignSystem.AppSpacing.screen)
        }
    }

    @ViewBuilder
    private var recentSearchesView: some View {
        if !recentSearches.isEmpty {
            VStack(spacing: 4) {
                HStack {
                    DesignSystem.SectionHeader(title: "Recent searches")
                    Spacer()
                    Button("Clear all") { recentSearches = [] }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(DesignSystem.AppColors.accent)
                        .frame(minHeight: 44)
                }
                ForEach(recentSearches, id: \.self) { recent in
                    HStack(spacing: 12) {
                        AppIconView(icon: .recent, size: .row)
                        Button(recent) { searchText = recent }
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Button {
                            recentSearches.removeAll { $0 == recent }
                        } label: {
                            AppIconView(icon: .clear, size: .row)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove recent search \(recent)")
                    }
                    .padding(.horizontal, 18)
                }
            }
        } else if let track = playback.currentTrack {
            VStack(alignment: .leading, spacing: 12) {
                DesignSystem.SectionHeader(title: "Pick up where you left off")
                DesignSystem.TrackRow(track: track, isCurrent: true, isPlaying: playback.isPlaying) {
                    onTrackSelected()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var playlistSearchResults: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return VStack(spacing: 8) {
            ForEach(matches) { playlist in
                HStack {
                    AppIconView(icon: .playlists)
                    Text(playlist.name)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Text("\(playlist.trackIDs.count) songs")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 14)
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 14)
    }

    private func download(_ result: RemoteSearchResult) {
        guard let url = result.downloadURL else { return }
        downloadingIDs.insert(result.id)
        Task {
            defer { downloadingIDs.remove(result.id) }
            do {
                _ = try await DownloadService.shared.download(from: url)
                downloadedIDs.insert(result.id)
                Haptics.notify()
            } catch {
                onlineError = error.localizedDescription
                Haptics.notify(.error)
            }
        }
    }

    private func scheduleOnlineSearch() {
        onlineSearchTask?.cancel()
        guard isOnline else {
            onlineResults = []
            onlineError = nil
            isSearchingOnline = false
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            onlineResults = []
            onlineError = nil
            isSearchingOnline = false
            return
        }
        onlineError = nil
        isSearchingOnline = true
        onlineSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let urls = feedURLs.compactMap(URL.init(string:))
            var searches = recentSearches.filter { $0.localizedCaseInsensitiveCompare(query) != .orderedSame }
            searches.insert(query, at: 0)
            recentSearches = Array(searches.prefix(8))
            do {
                let results = try await JSONFeedRemoteMusicSource(feedURLs: urls).search(query)
                guard !Task.isCancelled else { return }
                onlineResults = results
            } catch {
                guard !Task.isCancelled else { return }
                onlineResults = []
                onlineError = error.localizedDescription
            }
            isSearchingOnline = false
        }
    }

}

private enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"

    var id: String { rawValue }
}

private struct SearchTrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isOffline: Bool
    let select: () -> Void
    let playNext: () -> Void
    let addToQueue: () -> Void
    let searchText: String
    @State private var swipeOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                if displayOffset > 0 {
                    swipeButton(.playNext, label: "Play Next", action: playNext)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    swipeButton(
                        .favorite,
                        label: track.isFavorite ? "Remove Favorite" : "Favorite",
                        isActive: track.isFavorite
                    ) {
                        track.isFavorite.toggle()
                    }
                    swipeButton(.addQueue, label: "Add to Queue", action: addToQueue)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)

            DesignSystem.TrackRow(
                track: track,
                isCurrent: isCurrent,
                isPlaying: isPlaying,
                isOffline: isOffline,
                titleText: highlightedTitle,
                trailingMenu: AnyView(
                    Menu {
                        Button("Play Next", systemImage: AppIcon.playNext.symbolName(), action: playNext)
                        Button("Add to Queue", systemImage: AppIcon.addQueue.symbolName(), action: addToQueue)
                        Button(
                            track.isFavorite ? "Remove Favorite" : "Add to Favorites",
                            systemImage: AppIcon.favorite.symbolName(active: track.isFavorite)
                        ) {
                            track.isFavorite.toggle()
                        }
                    } label: {
                        AppIconView(icon: .more, size: .toolbar, weight: .semibold)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Song options")
                ),
                action: {
                    swipeOffset = 0
                    select()
                }
            )
            .offset(x: displayOffset)
        }
        .frame(height: 68)
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
        .contextMenu {
            Button("Play Next", systemImage: AppIcon.playNext.symbolName(), action: playNext)
            Button("Add to Queue", systemImage: AppIcon.addQueue.symbolName(), action: addToQueue)
            Button(
                track.isFavorite ? "Remove Favorite" : "Add to Favorites",
                systemImage: AppIcon.favorite.symbolName(active: track.isFavorite)
            ) {
                track.isFavorite.toggle()
            }
        }
    }

    private var highlightedTitle: Text {
        guard let range = track.title.range(of: searchText, options: .caseInsensitive) else {
            return Text(track.title)
        }
        return Text(String(track.title[..<range.lowerBound]))
            + Text(String(track.title[range])).foregroundColor(DesignSystem.AppColors.accent)
            + Text(String(track.title[range.upperBound...]))
    }

    private var displayOffset: CGFloat {
        min(max(swipeOffset + dragOffset, -96), 52)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let offset = swipeOffset + value.translation.width
                withAnimation(DesignSystem.Motion.spring) {
                    if offset <= -48 {
                        swipeOffset = -96
                    } else if offset >= 32 {
                        swipeOffset = 52
                    } else {
                        swipeOffset = 0
                    }
                }
            }
    }

    private func swipeButton(
        _ icon: AppIcon,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(DesignSystem.Motion.spring) {
                swipeOffset = 0
            }
        } label: {
            AppIconView(icon: icon, size: .row, weight: .semibold, isActive: isActive, color: DesignSystem.AppColors.accent)
                .frame(width: 44, height: 44)
                .background(DesignSystem.AppColors.accent.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private enum TrackListEmptyState {
    case library
    case favorites
}

private struct TrackGroup: Identifiable {
    let letter: String
    let tracks: [Track]
    var id: String { letter }
}

private struct TrackList: View {
    let tracks: [Track]
    let playlists: [Playlist]
    @ObservedObject var playback: PlaybackService
    let context: ModelContext
    let isOnline: Bool
    let showsDaypartGreeting: Bool
    let emptyState: TrackListEmptyState
    var showsFavoritesHeader: Bool = false
    let onImportFiles: () -> Void
    let onImportURL: () -> Void
    let reportError: (String) -> Void
    let onTrackSelected: () -> Void
    let onBrowseLibrary: () -> Void
    let onOpenSettings: () -> Void
    @State private var searchText = ""
    @State private var pendingDeletion: [Track] = []
    @State private var showingDeleteConfirmation = false
    @State private var playlistTrack: Track?
    @State private var showingCreatePlaylist = false
    @State private var trackToEdit: Track?
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @AppStorage("music.songSort") private var sort: SongSort = .title

    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        return tracks.filter { track in
            let searchable = [track.title, track.artist, track.albumTitle, track.originalFilename].joined(separator: " ").lowercased()
            return searchable.contains(searchText.lowercased())
        }
    }

    /// A–Z sections when sorted by title; one unlabeled section for other sorts.
    private var trackGroups: [TrackGroup] {
        guard sort == .title else {
            return [TrackGroup(letter: "", tracks: sort.sorted(filteredTracks))]
        }
        let grouped = Dictionary(grouping: filteredTracks) { track in
            let first = track.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased().first
            return first.map { $0.isLetter ? String($0) : "#" } ?? "#"
        }
        // Letters first, "#" last.
        let letters = grouped.keys.sorted { a, b in
            if a == "#" || b == "#" { return b == "#" && a != "#" }
            return a < b
        }
        return letters.map { letter in
            TrackGroup(letter: letter, tracks: SongSort.title.sorted(grouped[letter] ?? []))
        }
    }

    /// Songs in display order, used as the play queue.
    private var displayedTracks: [Track] {
        trackGroups.flatMap(\.tracks)
    }

    private var recentlyAddedAlbums: [Track] {
        var seenAlbums = Set<String>()
        return tracks.filter { track in
            let albumKey = "\(track.artist.localizedLowercase)|\(track.albumTitle.localizedLowercase)"
            return seenAlbums.insert(albumKey).inserted
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if showsDaypartGreeting && searchText.isEmpty {
                        TimelineView(.periodic(from: .now, by: 60 * 60)) { timeline in
                            let title = DaypartGreeting.title(at: timeline.date)
                            Text(title)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(DesignSystem.AppColors.primaryText)
                                .contentTransition(.opacity)
                                .animation(DesignSystem.Motion.spring, value: title)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .padding(.horizontal, 2)
                    }

                    if showsFavoritesHeader {
                        HStack(spacing: 12) {
                            Text("Your saved songs")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                            Spacer(minLength: 4)
                            Button {
                                if let first = filteredTracks.first {
                                    playback.play(first, from: filteredTracks)
                                    onTrackSelected()
                                    Haptics.impact(.medium)
                                }
                            } label: {
                                Label("Play", systemImage: AppIcon.play.symbolName())
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                            .buttonStyle(DesignSystem.PremiumPressStyle())
                            .disabled(filteredTracks.isEmpty)
                            Button {
                                guard !filteredTracks.isEmpty else { return }
                                playback.playShuffled(filteredTracks)
                                onTrackSelected()
                                Haptics.impact(.medium)
                            } label: {
                                AppIconView(icon: .shuffle, size: .toolbar)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Shuffle favorites")
                            .disabled(filteredTracks.isEmpty)
                        }
                        .padding(.top, 8)
                    } else if !filteredTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(filteredTracks.count) \(filteredTracks.count == 1 ? "track" : "tracks")")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                .textCase(.uppercase)
                                .tracking(1.2)
                                .padding(.horizontal, 2)

                            HStack(spacing: 12) {
                                Button {
                                    if let first = displayedTracks.first {
                                        playback.play(first, from: displayedTracks)
                                        onTrackSelected()
                                        Haptics.impact(.medium)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Play")
                                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    }
                                    .foregroundStyle(DesignSystem.AppColors.accentContrastText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(DesignSystem.AppColors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: DesignSystem.AppColors.accent.opacity(0.3), radius: 8, y: 3)
                                }
                                .buttonStyle(DesignSystem.PremiumPressStyle())

                                Button {
                                    guard !filteredTracks.isEmpty else { return }
                                    playback.playShuffled(filteredTracks)
                                    onTrackSelected()
                                    Haptics.impact(.medium)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Shuffle")
                                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    }
                                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .glassCard(cornerRadius: 14)
                                }
                                .buttonStyle(DesignSystem.PremiumPressStyle())
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if searchText.isEmpty && !recentlyAddedAlbums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(recentlyAddedAlbums) { album in
                                let albumTracks = tracks.filter {
                                    $0.artist == album.artist && $0.albumTitle == album.albumTitle
                                }
                                Button {
                                    if let firstTrack = albumTracks.first {
                                        playback.play(firstTrack, from: albumTracks)
                                        onTrackSelected()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        DesignSystem.ArtworkView(data: album.artworkData, size: 140, placeholderKey: album.albumTitle)
                                        Text(album.albumTitle)
                                            .font(.system(.headline, design: .rounded).weight(.semibold))
                                            .foregroundStyle(DesignSystem.AppColors.primaryText)
                                            .lineLimit(1)
                                            .frame(width: 140, alignment: .leading)
                                        Text(album.artist)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                            .lineLimit(1)
                                            .frame(width: 140, alignment: .leading)
                                    }
                                }
                                .buttonStyle(DesignSystem.PremiumPressStyle())
                                .accessibilityLabel("Play \(album.albumTitle) by \(album.artist)")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 212)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    DesignSystem.SectionHeader(title: "Recently Added")
                }
            }

            if filteredTracks.isEmpty {
                Section {
                    if !searchText.isEmpty {
                        DesignSystem.EmptyStateView(
                            title: "No search results",
                            message: "Try a different title, artist, or album.",
                            icon: .search,
                            actionTitle: "Clear Search",
                            actionIcon: .clear,
                            action: { searchText = "" }
                        )
                    } else if emptyState == .favorites {
                        DesignSystem.EmptyStateView(
                            title: "No favorites yet",
                            message: "Save songs you love and find them here.",
                            icon: .favorite,
                            actionTitle: "Browse Songs",
                            actionIcon: .songs,
                            action: onBrowseLibrary
                        )
                    } else {
                        DesignSystem.EmptyStateView(
                            title: isOnline ? "Your library is empty" : "You're offline",
                            message: isOnline ? "Import music to start building your library." : "Import music from Files to listen offline.",
                            icon: isOnline ? .library : .offline,
                            actionTitle: "Import from Files",
                            actionIcon: .files,
                            action: onImportFiles
                        )
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !filteredTracks.isEmpty {
                libraryToolsRow
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(trackGroups) { group in
                Section {
                    ForEach(group.tracks) { track in
                        trackRow(track)
                    }
                } header: {
                    if !group.letter.isEmpty {
                        Text(group.letter)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .id(group.letter)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.AppColors.background)
        .overlay(alignment: .trailing) {
            if sort == .title, !isSelecting, trackGroups.count > 4 {
                AlphabetIndex(letters: trackGroups.map(\.letter)) { letter in
                    proxy.scrollTo(letter, anchor: .top)
                }
            }
        }
        }
        .safeAreaPadding(.bottom, 16)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionActionBar
            }
        }
        .onChange(of: tracks.count) {
            selectedIDs.formIntersection(Set(tracks.map(\.id)))
        }
        .sheet(isPresented: $showingCreatePlaylist, onDismiss: {
            playlistTrack = nil
        }) {
            CreatePlaylistSheet(message: "The selected song will be added to the new playlist.") { name in
                createPlaylist(named: name)
            }
        }
        .sheet(item: $trackToEdit) { track in
            EditTrackView(track: track)
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Remove from Library?" : "Remove \(pendingDeletion.count) songs from Library?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                removeFromLibrary(pendingDeletion)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("Songs are removed from Music and your playlists. The original audio files in Files are not deleted.")
        }
    }

    // MARK: - Rows

    private func trackRow(_ track: Track) -> some View {
        let isSelected = selectedIDs.contains(track.id)
        let trailing: AnyView = isSelecting
            ? AnyView(
                AppIconView(icon: isSelected ? .success : .unselected, size: .row, isActive: isSelected,
                            color: isSelected ? DesignSystem.AppColors.accent : .secondary)
                    .frame(width: 44, height: 44)
            )
            : AnyView(
                SongOptionsMenu(
                    track: track,
                    playlists: playlists,
                    playback: playback,
                    context: context,
                    reportError: reportError,
                    deleteTrack: { confirmDeletion([track]) },
                    createPlaylist: {
                        playlistTrack = track
                        showingCreatePlaylist = true
                    },
                    editTrack: { trackToEdit = track }
                )
            )
        return DesignSystem.TrackRow(
            track: track,
            isCurrent: playback.currentTrack?.id == track.id,
            isPlaying: playback.isPlaying,
            isOffline: !isOnline,
            trailingMenu: trailing,
            actionAccessibilityLabel: isSelecting ? (isSelected ? "Deselect \(track.title)" : "Select \(track.title)") : nil
        ) {
            if isSelecting {
                if isSelected { selectedIDs.remove(track.id) } else { selectedIDs.insert(track.id) }
                Haptics.selection()
            } else {
                playback.play(track, from: displayedTracks)
                onTrackSelected()
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(isSelected ? DesignSystem.AppColors.accent.opacity(0.10) : Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                Button {
                    track.isFavorite.toggle()
                    Haptics.impact(.light)
                } label: {
                    Label(track.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: AppIcon.favorite.symbolName(active: track.isFavorite))
                }
                .tint(DesignSystem.AppColors.accent)
                Button {
                    playback.addToQueue(track)
                } label: {
                    Label("Add to Queue", systemImage: AppIcon.addQueue.symbolName())
                }
                .tint(DesignSystem.AppColors.accent)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isSelecting {
                Button {
                    playback.playNext(track)
                } label: {
                    Label("Play Next", systemImage: AppIcon.playNext.symbolName())
                }
                .tint(DesignSystem.AppColors.accent)
            }
        }
    }

    private var libraryToolsRow: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(SongSort.allCases) { option in
                        Label(option.rawValue, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Sort songs, currently \(sort.rawValue)")
            Spacer()
            if isSelecting {
                Button(selectedIDs.count == displayedTracks.count ? "Deselect All" : "Select All") {
                    selectedIDs = selectedIDs.count == displayedTracks.count ? [] : Set(displayedTracks.map(\.id))
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .frame(minHeight: 44)
            }
            Button(isSelecting ? "Done" : "Select") {
                withAnimation(DesignSystem.Motion.spring) {
                    isSelecting.toggle()
                    selectedIDs = []
                }
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(DesignSystem.AppColors.accent)
            .frame(minHeight: 44)
        }
    }

    private var selectedTracks: [Track] {
        displayedTracks.filter { selectedIDs.contains($0.id) }
    }

    private var selectionActionBar: some View {
        let none = selectedIDs.isEmpty
        return HStack(spacing: 0) {
            selectionButton("Play", icon: "play.fill") {
                guard let first = selectedTracks.first else { return }
                playback.play(first, from: selectedTracks)
                onTrackSelected()
                endSelection()
            }
            selectionButton("Queue", icon: AppIcon.addQueue.symbolName()) {
                selectedTracks.forEach(playback.addToQueue)
                Haptics.notify()
                endSelection()
            }
            selectionButton("Favorite", icon: "heart") {
                let makeFavorite = selectedTracks.contains { !$0.isFavorite }
                selectedTracks.forEach { $0.isFavorite = makeFavorite }
                Haptics.notify()
                endSelection()
            }
            Menu {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { add(selectedTracks, to: playlist) }
                }
                Button("New Playlist…", systemImage: AppIcon.createPlaylist.symbolName()) {
                    let ids = selectedTracks.map(\.id)
                    context.insert(Playlist(name: "New Playlist", trackIDs: ids))
                    try? context.save()
                    Haptics.notify()
                    endSelection()
                }
            } label: {
                selectionLabel("Playlist", icon: AppIcon.addToPlaylist.symbolName())
            }
            selectionButton("Delete", icon: "trash", role: .destructive) {
                confirmDeletion(selectedTracks)
            }
        }
        .disabled(none)
        .opacity(none ? 0.45 : 1)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .glassCard(cornerRadius: 22)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectionButton(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            selectionLabel(title, icon: icon, isDestructive: role == .destructive)
        }
        .buttonStyle(DesignSystem.PremiumPressStyle())
    }

    private func selectionLabel(_ title: String, icon: String, isDestructive: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            Text(title).font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(isDestructive ? DesignSystem.AppColors.danger : DesignSystem.AppColors.accent)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    private func endSelection() {
        withAnimation(DesignSystem.Motion.spring) {
            isSelecting = false
            selectedIDs = []
        }
    }

    // MARK: - Actions

    private func add(_ tracks: [Track], to playlist: Playlist) {
        let existing = Set(playlist.trackIDs)
        playlist.trackIDs.append(contentsOf: tracks.map(\.id).filter { !existing.contains($0) })
        do {
            try context.save()
            Haptics.notify()
            endSelection()
        } catch {
            reportError(error.localizedDescription)
        }
    }

    private func createPlaylist(named name: String) {
        let trackIDs = playlistTrack.map { [$0.id] } ?? []
        context.insert(Playlist(name: name, trackIDs: trackIDs))
        do {
            try context.save()
            Haptics.impact(.light)
        } catch {
            reportError(error.localizedDescription)
        }
    }

    private func confirmDeletion(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        pendingDeletion = tracks
        showingDeleteConfirmation = true
    }

    private func removeFromLibrary(_ tracks: [Track]) {
        let ids = Set(tracks.map(\.id))
        guard !ids.isEmpty else { return }
        // Stop/unqueue first so playback never touches a deleted model.
        playback.remove(trackIDs: ids)
        for playlist in playlists where playlist.trackIDs.contains(where: ids.contains) {
            playlist.trackIDs.removeAll(where: ids.contains)
        }
        if let albums = try? context.fetch(FetchDescriptor<Album>()) {
            for album in albums where album.trackIDs.contains(where: ids.contains) {
                album.trackIDs.removeAll(where: ids.contains)
                if album.trackIDs.isEmpty { context.delete(album) }
            }
        }
        tracks.forEach(context.delete)
        do {
            try context.save()
            Haptics.impact(.medium)
        } catch {
            reportError(error.localizedDescription)
        }
        pendingDeletion = []
        endSelection()
    }
}

enum SongSort: String, CaseIterable, Identifiable {
    case title = "Title"
    case artist = "Artist"
    case recentlyAdded = "Recently Added"
    case mostPlayed = "Most Played"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .title: "textformat"
        case .artist: "music.mic"
        case .recentlyAdded: "clock"
        case .mostPlayed: "flame"
        }
    }

    func sorted(_ tracks: [Track]) -> [Track] {
        func byTitle(_ a: Track, _ b: Track) -> Bool {
            a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        switch self {
        case .title:
            return tracks.sorted(by: byTitle)
        case .artist:
            return tracks.sorted {
                let order = $0.artist.localizedCaseInsensitiveCompare($1.artist)
                return order == .orderedSame ? byTitle($0, $1) : order == .orderedAscending
            }
        case .recentlyAdded:
            return tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .mostPlayed:
            return tracks.sorted { $0.playCount == $1.playCount ? byTitle($0, $1) : $0.playCount > $1.playCount }
        }
    }
}

/// Vertical A–Z strip: tap or drag to jump to a section.
private struct AlphabetIndex: View {
    let letters: [String]
    let jump: (String) -> Void
    @State private var current: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(current == letter ? DesignSystem.AppColors.accentContrastText : DesignSystem.AppColors.accent)
                        .frame(width: 18, height: 16)
                        .background(current == letter ? DesignSystem.AppColors.accent : .clear, in: Circle())
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let rowHeight: CGFloat = 16
                        let top = (geometry.size.height - rowHeight * CGFloat(letters.count)) / 2
                        let index = Int((value.location.y - top) / rowHeight)
                        guard letters.indices.contains(index), letters[index] != current else { return }
                        current = letters[index]
                        jump(letters[index])
                        Haptics.selection()
                    }
                    .onEnded { _ in current = nil }
            )
        }
        .frame(width: 22)
        .padding(.trailing, 2)
        .accessibilityElement()
        .accessibilityLabel("Section index")
        .accessibilityAdjustableAction { direction in
            let index = letters.firstIndex(of: current ?? letters.first ?? "") ?? 0
            let next = direction == .increment ? min(index + 1, letters.count - 1) : max(index - 1, 0)
            guard letters.indices.contains(next) else { return }
            current = letters[next]
            jump(letters[next])
        }
    }
}

private struct SongOptionsMenu: View {
    let track: Track
    let playlists: [Playlist]
    @ObservedObject var playback: PlaybackService
    let context: ModelContext
    let reportError: (String) -> Void
    let deleteTrack: () -> Void
    let createPlaylist: () -> Void
    var editTrack: (() -> Void)? = nil
    @State private var isPresented = false

    var body: some View {
        Menu {
            Button("Play Next", systemImage: AppIcon.playNext.symbolName()) {
                playback.playNext(track)
            }
            Button("Add to Queue", systemImage: AppIcon.addQueue.symbolName()) {
                playback.addToQueue(track)
            }
            Button(track.isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: AppIcon.favorite.symbolName(active: track.isFavorite)) {
                track.isFavorite.toggle()
            }
            Menu("Add to Playlist", systemImage: AppIcon.addToPlaylist.symbolName()) {
                if playlists.isEmpty {
                    Button("No playlists yet", systemImage: AppIcon.playlists.symbolName()) {}
                        .disabled(true)
                } else {
                    ForEach(playlists) { playlist in
                        Button(playlist.name) {
                            guard !playlist.trackIDs.contains(track.id) else { return }
                            playlist.trackIDs.append(track.id)
                            do { try context.save() }
                            catch { reportError(error.localizedDescription) }
                        }
                    }
                }
                Button("Create Playlist…", systemImage: AppIcon.createPlaylist.symbolName()) {
                    createPlaylist()
                }
            }
            if let editTrack {
                Button("Edit Info…", systemImage: "pencil", action: editTrack)
            }
            Button("Delete from Library", systemImage: AppIcon.delete.symbolName(), role: .destructive) {
                deleteTrack()
            }
        } label: {
            AppIconView(icon: .more, size: .toolbar, weight: .semibold, color: .secondary)
                .foregroundStyle(DesignSystem.AppColors.primaryText)
                .rotationEffect(.degrees(isPresented ? 90 : 0))
                .scaleEffect(isPresented ? 1.08 : 1)
                .symbolEffect(.bounce, value: isPresented)
                .frame(width: 44, height: 44)
                .glassCircle()
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [DesignSystem.AppColors.border, DesignSystem.AppColors.card, DesignSystem.AppColors.accent.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: DesignSystem.AppColors.accent.opacity(0.12), radius: 10, y: 3)
                .contentShape(Rectangle())
                .animation(DesignSystem.Motion.spring, value: isPresented)
        }
        .buttonStyle(DesignSystem.PremiumPressStyle())
        .accessibilityLabel("Song options")
        .onChange(of: isPresented) {
            if isPresented { Haptics.impact(.light) }
        }
    }
}

private struct AlbumList: View {
    let tracks: [Track]
    @ObservedObject var playback: PlaybackService
    let onImportFiles: () -> Void
    let onTrackSelected: () -> Void

    private var albums: [String: [Track]] {
        Dictionary(grouping: tracks) { "\($0.artist)|\($0.albumTitle)" }
    }

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = (geometry.size.width - 52) / 2
            ScrollView {
                if tracks.isEmpty {
                    DesignSystem.EmptyStateView(
                        title: "Your library is empty",
                        message: "Import music to see your albums here.",
                        icon: .albums,
                        actionTitle: "Import from Files",
                        actionIcon: .files,
                        action: onImportFiles
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(albums.keys.sorted(), id: \.self) { key in
                            if let albumTracks = albums[key], let first = albumTracks.first {
                                NavigationLink {
                                    TrackCollectionView(
                                        title: first.albumTitle,
                                        subtitle: first.artist,
                                        artworkData: albumTracks.lazy.compactMap(\.artworkData).first,
                                        tracks: albumTracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                                        playback: playback,
                                        onTrackSelected: onTrackSelected
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        DesignSystem.ArtworkView(
                                            data: first.artworkData,
                                            size: itemWidth,
                                            placeholderKey: first.albumTitle,
                                            cornerRadius: 20
                                        )
                                        Text(first.albumTitle)
                                            .font(.system(.headline, design: .rounded).weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(first.artist)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: itemWidth, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(DesignSystem.PremiumPressStyle())
                                .contextMenu {
                                    Button("Play", systemImage: AppIcon.play.symbolName()) {
                                        playback.play(first, from: albumTracks)
                                        onTrackSelected()
                                    }
                                    Button("Shuffle", systemImage: AppIcon.shuffle.symbolName()) {
                                        playback.playShuffled(albumTracks)
                                        onTrackSelected()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(DesignSystem.AppColors.background)
    }
}

private struct ArtistList: View {
    let tracks: [Track]
    @ObservedObject var playback: PlaybackService
    let onImportFiles: () -> Void
    let onTrackSelected: () -> Void

    var body: some View {
        List {
            if tracks.isEmpty {
                DesignSystem.EmptyStateView(
                    title: "Your library is empty",
                    message: "Import music to see artists here.",
                    icon: .artists,
                    actionTitle: "Import from Files",
                    actionIcon: .files,
                    action: onImportFiles
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(Dictionary(grouping: tracks, by: \.artist).keys.sorted(), id: \.self) { artist in
                    let artistTracks = tracks.filter { $0.artist == artist }
                        .sorted { ($0.albumTitle, $0.title) < ($1.albumTitle, $1.title) }
                    NavigationLink {
                        TrackCollectionView(
                            title: artist,
                            subtitle: "\(Set(artistTracks.map(\.albumTitle)).count) albums",
                            showsArtistAvatar: true,
                            tracks: artistTracks,
                            playback: playback,
                            onTrackSelected: onTrackSelected
                        )
                    } label: {
                        HStack(spacing: 12) {
                            DesignSystem.ArtistAvatar(name: artist, size: 56)
                            VStack(alignment: .leading) {
                                Text(artist).foregroundStyle(.primary)
                                Text("\(artistTracks.count) songs")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .contextMenu {
                        Button("Shuffle Artist", systemImage: AppIcon.shuffle.symbolName()) {
                            playback.playShuffled(artistTracks)
                            onTrackSelected()
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.AppColors.background)
    }
}

private struct PlaylistList: View {
    let tracks: [Track]
    let playlists: [Playlist]
    @ObservedObject var playback: PlaybackService
    let context: ModelContext
    let reportError: (String) -> Void
    let onTrackSelected: () -> Void
    let onCreatePlaylist: () -> Void
    @State private var selectedPlaylist: Playlist?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                Button(action: onCreatePlaylist) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(DesignSystem.AppColors.accent)
                            AppIconView(icon: .add, size: .toolbar, weight: .semibold, color: .white)
                        }
                        .frame(width: 56, height: 56)
                        Text("New Playlist")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .padding(12)
                .glassCard(cornerRadius: 20)
                .padding(.bottom, 12)

                DesignSystem.SectionHeader(title: "Smart Playlists")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(SmartPlaylist.allCases) { smart in
                        let smartTracks = smart.tracks(from: tracks)
                        NavigationLink {
                            TrackCollectionView(
                                title: smart.rawValue,
                                emptyMessage: smart.emptyMessage,
                                tracks: smartTracks,
                                playback: playback,
                                onTrackSelected: onTrackSelected
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: smart.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(DesignSystem.AppColors.accent)
                                    .frame(width: 40, height: 40)
                                    .background(DesignSystem.AppColors.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(smart.rawValue)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(smartTracks.count) songs")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .glassCard(cornerRadius: 18)
                        }
                        .buttonStyle(DesignSystem.PremiumPressStyle())
                    }
                }
                .padding(.bottom, 16)

                if !playlists.isEmpty {
                    DesignSystem.SectionHeader(title: "Your Playlists")
                }

                if playlists.isEmpty {
                    DesignSystem.EmptyStateView(
                        title: "No playlists yet",
                        message: "Create a playlist for any mood or moment.",
                        icon: .playlists,
                        actionTitle: "Create Playlist",
                        actionIcon: .createPlaylist,
                        action: onCreatePlaylist
                    )
                } else {
                    ForEach(playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: playlist, tracks: tracks)
                                    .frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.system(.headline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(playlist.trackIDs.count) songs")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                AppIconView(icon: .chevron, size: .row)
                            }
                            .frame(minHeight: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DesignSystem.PremiumPressStyle())
                        .contextMenu {
                            Button("Play", systemImage: AppIcon.play.symbolName()) {
                                play(playlist)
                            }
                            Button("Delete Playlist", systemImage: AppIcon.delete.symbolName(), role: .destructive) {
                                context.delete(playlist)
                                do { try context.save() }
                                catch { reportError(error.localizedDescription) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(DesignSystem.AppColors.card, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(DesignSystem.AppColors.background)
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(
                playlist: playlist,
                tracks: tracks,
                playback: playback,
                context: context,
                onTrackSelected: onTrackSelected
            )
            .presentationCornerRadius(28)
        }
    }

    private func play(_ playlist: Playlist) {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let items = playlist.trackIDs.compactMap { lookup[$0] }
        guard let first = items.first else { return }
        playback.play(first, from: items)
        onTrackSelected()
    }
}

private struct PlaylistArtwork: View {
    let playlist: Playlist
    let tracks: [Track]

    private var artworkTracks: [Track] {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return Array(playlist.trackIDs.compactMap { lookup[$0] }.prefix(4))
    }

    var body: some View {
        GeometryReader { geometry in
            let side = (geometry.size.width - 2) / 2
            LazyVGrid(columns: [GridItem(.fixed(side)), GridItem(.fixed(side))], spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    if artworkTracks.indices.contains(index) {
                        DesignSystem.ArtworkView(
                            data: artworkTracks[index].artworkData,
                            size: side,
                            placeholderKey: artworkTracks[index].albumTitle,
                            cornerRadius: 5
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(DesignSystem.AppColors.card)
                            .overlay {
                                AppIconView(icon: .songs, size: .row, color: DesignSystem.AppColors.secondaryText.opacity(0.55))
                            }
                            .frame(width: side, height: side)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddSongs = false
    let playlist: Playlist
    let tracks: [Track]
    @ObservedObject var playback: PlaybackService
    let context: ModelContext
    let onTrackSelected: () -> Void

    private var playlistTracks: [Track] {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        PlaylistArtwork(playlist: playlist, tracks: tracks)
                            .frame(width: 200, height: 200)
                        Text(playlist.name)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(playlistTracks.count) songs · \(durationText)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            DesignSystem.GlassButton(title: "Play", icon: .play, action: playPlaylist, style: .primary)
                            DesignSystem.GlassButton(title: "Shuffle", icon: .shuffle, action: shufflePlaylist, style: .secondary)
                        }
                        Button {
                            showingAddSongs = true
                        } label: {
                            Label("Add songs", systemImage: AppIcon.add.symbolName())
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(DesignSystem.AppColors.accent)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("Songs") {
                    ForEach(playlistTracks) { track in
                        DesignSystem.TrackRow(
                            track: track,
                            isCurrent: playback.currentTrack?.id == track.id,
                            isPlaying: playback.isPlaying
                        ) {
                            playback.play(track, from: playlistTracks)
                            onTrackSelected()
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: moveTracks)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.AppColors.background)
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 18)
            }
            .sheet(isPresented: $showingAddSongs) {
                AddSongsToPlaylistView(playlist: playlist, tracks: tracks, context: context)
                    .presentationCornerRadius(28)
            }
        }
    }

    private var durationText: String {
        let totalMinutes = Int(playlistTracks.reduce(0) { $0 + $1.duration } / 60)
        return "\(totalMinutes / 60) hr \(totalMinutes % 60) min"
    }

    private func playPlaylist() {
        guard let first = playlistTracks.first else { return }
        playback.play(first, from: playlistTracks)
        onTrackSelected()
    }

    private func shufflePlaylist() {
        guard !playlistTracks.isEmpty else { return }
        playback.playShuffled(playlistTracks)
        onTrackSelected()
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        var ids = playlist.trackIDs
        ids.move(fromOffsets: source, toOffset: destination)
        playlist.trackIDs = ids
        do { try context.save() }
        catch { playback.errorMessage = error.localizedDescription }
    }
}

private struct AddSongsToPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<UUID>()
    @State private var errorMessage: String?
    let playlist: Playlist
    let tracks: [Track]
    let context: ModelContext

    private var availableTracks: [Track] {
        tracks.filter { !playlist.trackIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableTracks) { track in
                    Button {
                        if selectedIDs.contains(track.id) {
                            selectedIDs.remove(track.id)
                        } else {
                            selectedIDs.insert(track.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            AppIconView(
                                icon: selectedIDs.contains(track.id) ? .success : .unselected,
                                size: .row,
                                isActive: selectedIDs.contains(track.id),
                                color: selectedIDs.contains(track.id) ? DesignSystem.AppColors.accent : .secondary
                            )
                                .frame(width: 44, height: 44)
                            DesignSystem.ArtworkView(data: track.artworkData, size: 44, placeholderKey: track.albumTitle)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.system(.headline, design: .rounded))
                                Text(track.artist).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.AppColors.background)
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                DesignSystem.GlassButton(
                    title: "Add \(selectedIDs.count) songs",
                    icon: .add,
                    action: addSelectedSongs,
                    style: .primary
                )
                .disabled(selectedIDs.isEmpty)
                .opacity(selectedIDs.isEmpty ? 0.5 : 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .alert("Couldn’t add songs", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func addSelectedSongs() {
        playlist.trackIDs.append(contentsOf: availableTracks.filter { selectedIDs.contains($0.id) }.map(\.id))
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let message: String?
    let onCreate: (String) -> Void

    init(message: String? = nil, onCreate: @escaping (String) -> Void) {
        self.message = message
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("New Playlist")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(DesignSystem.AppColors.primaryText)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        AppIconView(icon: .clear, size: .row, weight: .regular)
                            .frame(width: 44, height: 44)
                            .glassCircle()
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityLabel("Close")
                }

                HStack(spacing: 10) {
                    TextField("Playlist name", text: $name)
                        .font(.system(.body, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(createPlaylist)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .glassCapsule()
                        .accessibilityLabel("Playlist name")

                    Button(action: createPlaylist) {
                        AppIconView(icon: .checkmark, size: .row, weight: .semibold, color: DesignSystem.AppColors.accent)
                            .frame(width: 44, height: 44)
                            .glassCircle()
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Create playlist")
                }

                if let message {
                    Text(message)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .glassCard(cornerRadius: 26)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.AppColors.background.ignoresSafeArea())
        .presentationDetents([.height(message == nil ? 230 : 270)])
        .presentationDragIndicator(.visible)
    }

    private func createPlaylist() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName)
        dismiss()
    }
}

private struct MiniPlayer: View {
    @ObservedObject var playback: PlaybackService
    let open: () -> Void

    var body: some View {
        if let track = playback.currentTrack {
            HStack(spacing: 10) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        DesignSystem.ArtworkView(data: track.artworkData, size: 46, placeholderKey: track.albumTitle, cornerRadius: 12)
                            .overlay(alignment: .bottomTrailing) {
                                if playback.isPlaying {
                                    Circle()
                                        .fill(DesignSystem.AppColors.accent)
                                        .frame(width: 8, height: 8)
                                        .padding(3)
                                        .background(.black.opacity(0.6), in: Circle())
                                        .offset(x: 2, y: 2)
                                }
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(DesignSystem.AppColors.primaryText)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())

                // Play / Pause
                Button {
                    withAnimation(DesignSystem.Motion.spring) {
                        playback.togglePlayback()
                    }
                    Haptics.impact(.medium)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(playback.isPlaying ? DesignSystem.AppColors.accent : DesignSystem.AppColors.primaryText)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                // Next
                Button {
                    playback.next()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .accessibilityLabel("Next track")
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
            .glassCard(cornerRadius: 24)
            .overlay(alignment: .bottom) {
                MiniProgressBar(clock: playback.clock, duration: track.duration)
                .frame(height: 2.5)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(
                color: Color.black.opacity(0.18),
                radius: 16,
                x: 0,
                y: 6
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            playback.next()
                            Haptics.impact(.medium)
                        } else if value.translation.width > 40 {
                            playback.previous()
                            Haptics.impact(.medium)
                        } else if value.translation.height < -30 {
                            open()
                        }
                    }
            )
        }
    }
}

private struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var playback: PlaybackService
    let isOnline: Bool
    let playlists: [Playlist]
    let context: ModelContext
    let openSettings: () -> Void
    let mergeTrack: (Track) -> Void
    @State private var dismissalOffset = CGSize.zero
    @State private var isDismissing = false
    @State private var showingOptions = false
    @State private var showingCreatePlaylist = false
    @State private var showingQueue = false
    @State private var trackToEdit: Track?

    private func showQueue() { showingQueue = true }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // Top Sheet Indicator
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 38, height: 5)
                    .padding(.top, 4)

                // Top Navigation Bar
                HStack {
                    Button {
                        dismissPlayer(direction: .down, width: geometry.size.width)
                    } label: {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(DesignSystem.AppColors.primaryText)
                            .frame(width: 44, height: 44)
                            .glassCircle()
                    }
                    .buttonStyle(DesignSystem.PremiumPressStyle())
                    .accessibilityLabel("Close Now Playing")

                    Spacer()

                    VStack(spacing: 2) {
                        Text("NOW PLAYING")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(DesignSystem.AppColors.secondaryText)
                    }

                    Spacer()

                    Menu {
                        Button("Show queue", systemImage: AppIcon.queue.symbolName()) {
                            showQueue()
                        }
                        if let track = playback.currentTrack {
                            Button(track.isFavorite ? "Remove Favorite" : "Add to Favorites", systemImage: AppIcon.favorite.symbolName(active: track.isFavorite)) {
                                withAnimation(DesignSystem.Motion.spring) {
                                    track.isFavorite.toggle()
                                }
                                Haptics.impact(.light)
                            }
                            Menu("Add to Playlist", systemImage: AppIcon.addToPlaylist.symbolName()) {
                                if playlists.isEmpty {
                                    Button("No playlists yet", systemImage: AppIcon.playlists.symbolName()) {}
                                        .disabled(true)
                                } else {
                                    ForEach(playlists) { playlist in
                                        Button(playlist.name) {
                                            add(track, to: playlist)
                                        }
                                    }
                                }
                                Button("Create Playlist…", systemImage: AppIcon.createPlaylist.symbolName()) {
                                    showingCreatePlaylist = true
                                }
                            }
                            Button("Edit Info…", systemImage: "pencil") {
                                trackToEdit = track
                            }
                            Button("Merge Songs…", systemImage: AppIcon.merge.symbolName()) {
                                mergeTrack(track)
                            }
                        }
                        Button("Settings", systemImage: AppIcon.settings.symbolName()) {
                            openSettings()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DesignSystem.AppColors.primaryText)
                            .frame(width: 44, height: 44)
                            .glassCircle()
                    }
                    .accessibilityLabel("More options")
                }

                Spacer(minLength: 0)

                if let track = playback.currentTrack {
                    VStack(spacing: 18) {
                        // Artwork with breathing scale, drop shadow, and horizontal swipe
                        DesignSystem.ArtworkView(
                            data: track.artworkData,
                            size: min(geometry.size.width - 44, 320),
                            placeholderKey: track.albumTitle,
                            cornerRadius: 26
                        )
                        .scaleEffect(playback.isPlaying ? 1.0 : 0.88)
                        .shadow(
                            color: DesignSystem.AppColors.accent.opacity(playback.isPlaying ? 0.35 : 0.1),
                            radius: playback.isPlaying ? 24 : 10,
                            y: playback.isPlaying ? 12 : 6
                        )
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: playback.isPlaying)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { val in
                                    if val.translation.width < -40 {
                                        playback.next()
                                        Haptics.impact(.medium)
                                    } else if val.translation.width > 40 {
                                        playback.previous()
                                        Haptics.impact(.medium)
                                    }
                                }
                        )

                        // Title, Artist and Heart Favorite Button
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                    track.isFavorite.toggle()
                                }
                                Haptics.impact(.medium)
                            } label: {
                                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(track.isFavorite ? Color.pink : DesignSystem.AppColors.secondaryText)
                                    .scaleEffect(track.isFavorite ? 1.15 : 1.0)
                                    .frame(width: 46, height: 46)
                                    .glassCircle()
                            }
                            .buttonStyle(DesignSystem.PremiumPressStyle())
                            .accessibilityLabel(track.isFavorite ? "Remove from favorites" : "Add to favorites")
                        }
                        .padding(.horizontal, 4)

                        Scrubber(playback: playback, clock: playback.clock, duration: track.duration)

                        // Playback Controls
                        PlaybackControlPanel(playback: playback, showQueue: showQueue)
                    }
                    .id(track.id)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: playback.trackTransitionDirection == .next ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: playback.trackTransitionDirection == .next ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                    )
                    .animation(DesignSystem.Motion.spring, value: playback.currentTrack?.id)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.AppSpacing.screen)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(dismissalOffset)
            .scaleEffect(isDismissing ? 0.94 : 1)
            .opacity(isDismissing ? 0.72 : 1)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        if value.translation.width > 90 && abs(value.translation.width) > abs(value.translation.height) {
                            dismissPlayer(direction: .right, width: geometry.size.width)
                        } else if value.translation.height > 100 && abs(value.translation.width) < 70 {
                            dismissPlayer(direction: .down, width: geometry.size.width)
                        }
                    }
            )
        }
        .background {
            ZStack {
                AnimatedArtworkBackground()
                if let data = playback.currentTrack?.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .blur(radius: 54)
                        .opacity(0.35)
                        .overlay(DesignSystem.AppColors.accent.opacity(0.08))
                } else {
                    RadialGradient(
                        colors: [DesignSystem.AppColors.accent.opacity(0.22), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                    .blur(radius: 30)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingQueue) {
            QueueView(playback: playback)
        }
        .sheet(item: $trackToEdit) { track in
            EditTrackView(track: track)
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            CreatePlaylistSheet(message: "The currently playing song will be added to the new playlist.") { name in
                createPlaylistForCurrentTrack(named: name)
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private func add(_ track: Track, to playlist: Playlist) {
        guard !playlist.trackIDs.contains(track.id) else { return }
        playlist.trackIDs.append(track.id)
        do {
            try context.save()
            Haptics.impact(.light)
        } catch {
            playback.errorMessage = error.localizedDescription
        }
    }

    private func createPlaylistForCurrentTrack(named name: String) {
        guard let track = playback.currentTrack else { return }
        context.insert(Playlist(name: name, trackIDs: [track.id]))
        do {
            try context.save()
            Haptics.impact(.light)
        } catch {
            playback.errorMessage = error.localizedDescription
        }
    }

    private func dismissPlayer(
        direction: DismissDirection = .right,
        width: CGFloat
    ) {
        guard !isDismissing else { return }
        withAnimation(DesignSystem.Motion.spring) {
            isDismissing = true
            dismissalOffset = direction == .right
                ? CGSize(width: width + 40, height: 0)
                : CGSize(width: 0, height: 240)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            dismiss()
        }
    }

    private enum DismissDirection: Equatable {
        case right
        case down
    }
}

private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(Int(seconds), 0)
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
}

private struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var playback: PlaybackService

    var body: some View {
        NavigationStack {
            List {
                ForEach(playback.queue) { track in
                    DesignSystem.TrackRow(
                        track: track,
                        isCurrent: track.id == playback.currentTrack?.id,
                        isPlaying: playback.isPlaying,
                        trailingMenu: AnyView(
                            Menu {
                                Button("Play Next", systemImage: AppIcon.playNext.symbolName()) {
                                    playback.playNext(track)
                                }
                                Button("Add to Queue", systemImage: AppIcon.addQueue.symbolName()) {
                                    playback.addToQueue(track)
                                }
                            } label: {
                                AppIconView(icon: .more, size: .toolbar, weight: .semibold)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Song options")
                        )
                    ) {
                        playback.play(track, from: playback.queue)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            track.isFavorite.toggle()
                        } label: {
                            Label(
                                track.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: AppIcon.favorite.symbolName(active: track.isFavorite)
                            )
                        }
                        .tint(DesignSystem.AppColors.accent)

                        Button {
                            playback.addToQueue(track)
                        } label: {
                            Label("Add to Queue", systemImage: AppIcon.addQueue.symbolName())
                        }
                        .tint(DesignSystem.AppColors.accent)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            playback.playNext(track)
                        } label: {
                            Label("Play Next", systemImage: AppIcon.playNext.symbolName())
                        }
                        .tint(DesignSystem.AppColors.accent)
                    }
                    .contextMenu {
                        Button("Play Next", systemImage: AppIcon.playNext.symbolName()) {
                            playback.playNext(track)
                        }
                        Button("Add to Queue", systemImage: AppIcon.addQueue.symbolName()) {
                            playback.addToQueue(track)
                        }
                    }
                }
                .onMove(perform: playback.moveQueue)
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }
}

/// Observes only the clock, so the 2 Hz tick doesn't re-render the whole mini player.
private struct MiniProgressBar: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double

    var body: some View {
        let progress = duration > 0 ? min(max(clock.elapsed / duration, 0), 1) : 0
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                DesignSystem.AppColors.border
                DesignSystem.AppColors.accent
                    .frame(width: geometry.size.width * progress)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// Holds its own value while dragging and seeks once on release, so the
/// periodic time update can't fight the user's finger.
private struct Scrubber: View {
    @ObservedObject var playback: PlaybackService
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? clock.elapsed
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { shown }, set: { dragValue = $0 }),
                in: 0...max(duration, 1)
            ) { editing in
                if !editing, let dragValue {
                    playback.seek(to: dragValue)
                    self.dragValue = nil
                    Haptics.impact(.light)
                }
            }
            .tint(DesignSystem.AppColors.accent)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(shown)) of \(formatTime(duration))")

            HStack {
                Text(formatTime(shown))
                Spacer()
                Text("−\(formatTime(max(duration - shown, 0)))")
            }
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(DesignSystem.AppColors.secondaryText)
        }
    }
}
