import SwiftData
import SwiftUI

struct MergeDuplicatesView: View {
    let duplicates: [(Track, Track)]
    let onMerge: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(duplicates.indices, id: \.self) { index in
                    let pair = duplicates[index]
                    VStack(alignment: .leading) {
                        Text(pair.0.title)
                        Text("\(pair.0.artist) · \(pair.0.albumTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Merge duplicates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Merge") { onMerge() }
                }
            }
        }
    }
}

struct PlaylistMergeView: View {
    let playlists: [Playlist]
    let onMerge: (String) -> Void

    @State private var name = "Merged Playlist"

    var body: some View {
        NavigationStack {
            Form {
                TextField("New playlist name", text: $name)
            }
            .navigationTitle("Merge playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        onMerge(name)
                    }
                }
            }
        }
    }
}

struct AudioMergeView: View {
    let tracks: [Track]
    @State private var selectedTrackIDs: Set<UUID>
    @State private var crossfade = 10.0
    @State private var outputName = "Merged Audio"
    @State private var isExporting = false
    @State private var errorMessage: String?
    let onComplete: (URL?) -> Void

    init(
        tracks: [Track],
        initiallySelectedTrackIDs: Set<UUID>,
        onComplete: @escaping (URL?) -> Void
    ) {
        self.tracks = tracks
        self.onComplete = onComplete
        _selectedTrackIDs = State(initialValue: initiallySelectedTrackIDs)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select songs")
                                .font(DesignSystem.largeTitle)
                                .foregroundStyle(DesignSystem.AppColors.primaryText)
                            Text("\(selectedTrackIDs.count) selected")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        }

                        VStack(spacing: 8) {
                            ForEach(tracks) { track in
                        DesignSystem.TrackRow(
                            track: track,
                            isCurrent: false,
                            trailingMenu: AnyView(
                                Button(action: { toggleSelection(for: track) }) {
                                    AppIconView(
                                        icon: selectedTrackIDs.contains(track.id) ? .success : .unselected,
                                        size: .row,
                                        weight: .regular,
                                        isActive: selectedTrackIDs.contains(track.id),
                                        color: selectedTrackIDs.contains(track.id) ? DesignSystem.AppColors.accent : .secondary
                                    )
                                        .frame(width: 44, height: 44)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(selectedTrackIDs.contains(track.id) ? "Deselect \(track.title)" : "Select \(track.title)")
                            ),
                            actionAccessibilityLabel: selectedTrackIDs.contains(track.id) ? "Deselect \(track.title)" : "Select \(track.title)"
                        ) {
                            toggleSelection(for: track)
                        }
                            }
                        }
                        .padding(8)
                        .glassCard(cornerRadius: DesignSystem.AppRadius.card)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Crossfade")
                                .font(DesignSystem.headline)
                                .foregroundStyle(DesignSystem.AppColors.primaryText)
                            HStack {
                                Button {
                                    crossfade = max(0, crossfade - 1)
                                } label: {
                                    AppIconView(icon: .remove)
                                        .frame(width: 44, height: 44)
                                        .glassCircle()
                                }
                                .accessibilityLabel("Decrease crossfade")
                                Spacer()
                                Text("\(Int(crossfade))s")
                                    .font(DesignSystem.navigationTitle.monospacedDigit())
                                    .foregroundStyle(DesignSystem.AppColors.primaryText)
                                    .contentTransition(.numericText())
                                Spacer()
                                Button {
                                    crossfade = min(10, crossfade + 1)
                                } label: {
                                    AppIconView(icon: .add)
                                        .frame(width: 44, height: 44)
                                        .glassCircle()
                                }
                                .accessibilityLabel("Increase crossfade")
                            }
                            Text("A new audio file is created. Your originals are kept.")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DesignSystem.AppSpacing.s16)
                        .glassCard(cornerRadius: DesignSystem.AppRadius.card)

                        TextField("Output name", text: $outputName)
                            .font(DesignSystem.body)
                            .padding(DesignSystem.AppSpacing.s16)
                            .glassCard(cornerRadius: DesignSystem.AppRadius.card)

                        if isExporting {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(DesignSystem.AppColors.accent)
                                Text("Merging your audio…")
                                    .font(DesignSystem.subhead)
                                    .foregroundStyle(DesignSystem.AppColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, DesignSystem.AppSpacing.screen)
                    .padding(.top, DesignSystem.AppSpacing.s16)
                    .padding(.bottom, 24)
                }
                Button(action: exportSelectedTracks) {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView().tint(DesignSystem.AppColors.accentContrastText)
                        } else {
                            AppIconView(icon: .merge, color: DesignSystem.AppColors.accentContrastText)
                        }
                        Text(isExporting ? "Merging…" : "Merge \(selectedTrackIDs.count) songs")
                            .font(DesignSystem.body.weight(.semibold))
                    }
                    .foregroundStyle(DesignSystem.AppColors.accentContrastText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(DesignSystem.AppColors.accent, in: Capsule())
                }
                .buttonStyle(DesignSystem.PremiumPressStyle())
                .disabled(selectedTrackIDs.count < 2 || outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExporting)
                .opacity(selectedTrackIDs.count < 2 || outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .padding(.horizontal, DesignSystem.AppSpacing.screen)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(AnimatedArtworkBackground())
            .navigationTitle("Merge audio")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t merge audio", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .interactiveDismissDisabled(isExporting)
        }
    }

    private func exportSelectedTracks() {
        let selectedTracks = tracks.filter { selectedTrackIDs.contains($0.id) }
        Task {
            isExporting = true
            defer { isExporting = false }
            do {
                let url = try await MergeService().exportMergedAudio(
                    from: selectedTracks,
                    crossfade: crossfade,
                    outputName: outputName
                )
                onComplete(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleSelection(for track: Track) {
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
        } else {
            selectedTrackIDs.insert(track.id)
        }
        Haptics.selection()
    }
}
