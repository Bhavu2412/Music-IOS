import AVFoundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class URLImportViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var isURLValid = false
    var modelContext: ModelContext?

    private let downloadService: any DownloadServicing
    private let libraryService: any LibraryServicing

    init(
        downloadService: some DownloadServicing,
        libraryService: some LibraryServicing,
        modelContext: ModelContext? = nil
    ) {
        self.downloadService = downloadService
        self.libraryService = libraryService
        self.modelContext = modelContext
    }

    convenience init(modelContext: ModelContext? = nil) {
        self.init(
            downloadService: DownloadService.shared,
            libraryService: LibraryService(),
            modelContext: modelContext
        )
    }

    func validateURL() -> Bool {
        guard let url = URL(string: urlText), url.scheme != nil, url.host != nil else { return false }
        isURLValid = true
        return true
    }

    func beginImport() async {
        guard validateURL(), let url = URL(string: urlText) else {
            errorMessage = "Enter a valid direct audio URL."
            return
        }

        let allowedTypes = ["audio/mpeg", "audio/mp4", "audio/aac", "audio/wav", "audio/flac", "audio/x-flac", "audio/x-wav"]
        do {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                let isAllowed = allowedTypes.contains { type.lowercased().contains($0) }
                if !isAllowed && !type.isEmpty {
                    throw URLError(.unsupportedURL)
                }
            }

            isDownloading = true
            progress = 0.1
            let downloaded = try await downloadService.download(from: url)
            isDownloading = false
            progress = 1
            let bookmark = try downloaded.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let title = downloaded.deletingPathExtension().lastPathComponent
            let track = Track(
                title: title,
                artist: "Unknown Artist",
                albumTitle: "Unknown Album",
                duration: 0,
                artworkData: nil,
                bookmarkData: bookmark,
                originalFilename: downloaded.lastPathComponent,
                isDownloaded: true,
                isAvailableOffline: true,
                remoteURLString: url.absoluteString
            )
            guard let context = modelContext else {
                errorMessage = "Unable to save the imported track to the library."
                return
            }
            context.insert(track)
            try context.save()
        } catch {
            isDownloading = false
            progress = 0
            errorMessage = error.localizedDescription
        }
    }
}

struct URLImportView: View {
    @StateObject private var viewModel = URLImportViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var connectivity = ConnectivityService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s24) {
                    if !connectivity.isOnline {
                        HStack(spacing: 8) {
                            AppIconView(icon: .offline)
                            Text("Connect to the internet to import from a link.")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.AppSpacing.s12) {
                        Text("Direct audio URL")
                            .font(DesignSystem.title)
                            .foregroundStyle(DesignSystem.AppColors.primaryText)
                        HStack(spacing: 8) {
                            DesignSystem.GlassSearchBar(
                                text: Binding(
                                    get: { viewModel.urlText },
                                    set: { viewModel.urlText = $0 }
                                ),
                                placeholder: "https://example.com/song.mp3"
                            )
                            Button {
                                viewModel.urlText = UIPasteboard.general.string ?? ""
                            } label: {
                                AppIconView(icon: .paste)
                                    .frame(width: 44, height: 44)
                                    .glassCircle()
                            }
                            .buttonStyle(DesignSystem.PremiumPressStyle())
                            .accessibilityLabel("Paste URL")
                        }

                        if viewModel.isURLValid {
                            Label("URL looks valid", systemImage: AppIcon.success.symbolName())
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.success)
                        } else if let message = viewModel.errorMessage {
                            Label(message, systemImage: AppIcon.error.symbolName())
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Paste a direct link to an audio file.")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        }
                    }
                    .padding(DesignSystem.AppSpacing.s16)
                    .glassCard(cornerRadius: DesignSystem.AppRadius.card)

                    if viewModel.isDownloading {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: viewModel.progress, total: 1.0)
                                .tint(DesignSystem.AppColors.accent)
                            Text("Downloading…")
                                .font(DesignSystem.subhead)
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        }
                        .padding(DesignSystem.AppSpacing.s16)
                        .glassCard(cornerRadius: DesignSystem.AppRadius.card)
                    }

                    DesignSystem.GlassButton(
                        title: viewModel.isDownloading ? "Downloading…" : "Download",
                        icon: .download,
                        action: {
                            viewModel.modelContext = modelContext
                            Task { await viewModel.beginImport() }
                        },
                        style: .primary
                    )
                    .disabled(!connectivity.isOnline || viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isDownloading)
                    .opacity(!connectivity.isOnline ? 0.45 : 1)
                }
                .padding(.horizontal, DesignSystem.AppSpacing.screen)
                .padding(.top, DesignSystem.AppSpacing.s16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AnimatedArtworkBackground())
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        AppIconView(icon: .clear)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
        }
        .onChange(of: viewModel.urlText) {
            viewModel.errorMessage = nil
            viewModel.isURLValid = false
            _ = viewModel.validateURL()
        }
    }
}
