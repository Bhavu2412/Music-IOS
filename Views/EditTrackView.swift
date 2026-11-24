import PhotosUI
import SwiftData
import SwiftUI

/// Edits a track's tags and artwork. Changes apply only on Save.
struct EditTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let track: Track

    @State private var title: String
    @State private var artist: String
    @State private var albumTitle: String
    @State private var artworkData: Data?
    @State private var lyrics: String
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _albumTitle = State(initialValue: track.albumTitle)
        _artworkData = State(initialValue: track.artworkData)
        _lyrics = State(initialValue: track.lyrics ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            DesignSystem.ArtworkView(data: artworkData, size: 160, placeholderKey: albumTitle, cornerRadius: 20)
                            HStack(spacing: 16) {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Label(artworkData == nil ? "Add Artwork" : "Change Artwork", systemImage: "photo")
                                }
                                if artworkData != nil {
                                    Button("Remove", role: .destructive) { artworkData = nil }
                                }
                            }
                            .font(DesignSystem.subhead.weight(.semibold))
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Details") {
                    LabeledContent("Title") {
                        TextField("Title", text: $title).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Artist") {
                        TextField("Artist", text: $artist).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Album") {
                        TextField("Album", text: $albumTitle).multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    TextEditor(text: $lyrics)
                        .font(.system(.body, design: .rounded))
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if lyrics.isEmpty {
                                Text("Paste lyrics here")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Lyrics")
                } footer: {
                    Text("Plain text, or LRC with timestamps like [01:23.45] to scroll along with the song.")
                }

                Section("File") {
                    LabeledContent("Name", value: track.originalFilename)
                    LabeledContent("Plays", value: "\(track.playCount)")
                    if let bitrate = track.bitrate, bitrate > 0 {
                        LabeledContent("Bitrate", value: "\(Int(bitrate / 1000)) kbps")
                    }
                }
            }
            .navigationTitle("Edit Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onChange(of: photoItem) {
                Task { await loadArtwork() }
            }
            .alert("Couldn’t save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadArtwork() async {
        guard let photoItem,
              let data = try? await photoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Store a square 600 px JPEG: plenty for the UI and the lock screen, small in the database.
        let side: CGFloat = 600
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let scaled = renderer.jpegData(withCompressionQuality: 0.85) { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        artworkData = scaled
    }

    private func save() {
        func clean(_ value: String, fallback: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
        track.title = clean(title, fallback: track.title)
        track.artist = clean(artist, fallback: "Unknown Artist")
        track.albumTitle = clean(albumTitle, fallback: "Unknown Album")
        track.artworkData = artworkData
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        track.lyrics = trimmedLyrics.isEmpty ? nil : trimmedLyrics
        do {
            try modelContext.save()
            Haptics.notify()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
