import AVFoundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class URLImportViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isDownloading = false
    @Published var didFinish = false
    @Published var errorMessage: String?
    @Published var isURLValid = false
    var modelContext: ModelContext?

    private let downloadService: any DownloadServicing

    init(downloadService: any DownloadServicing, modelContext: ModelContext? = nil) {
        self.downloadService = downloadService
        self.modelContext = modelContext
    }

    convenience init(modelContext: ModelContext? = nil) {
        self.init(downloadService: DownloadService.shared, modelContext: modelContext)
    }

    @discardableResult
    func validateURL() -> Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed)
        isURLValid = ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && url?.host?.isEmpty == false
        return isURLValid
    }

    func beginImport() async {
        guard validateURL(), let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
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
            // Downloads in the background and imports into the library when done.
            _ = try await downloadService.download(from: url)
            isDownloading = false
            didFinish = true
            Haptics.notify()
        } catch {
            isDownloading = false
            errorMessage = error.localizedDescription
        }
    }
}

struct URLImportView: View {
    @StateObject private var viewModel = URLImportViewModel()
    @ObservedObject private var downloads = DownloadService.shared
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
                            let fraction = URL(string: viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines))
                                .flatMap { downloads.progress[$0] } ?? 0
                            ProgressView(value: fraction)
                                .tint(DesignSystem.AppColors.accent)
                            Text(fraction > 0 ? "Downloading… \(Int(fraction * 100))%" : "Starting download…")
                                .font(DesignSystem.subhead.monospacedDigit())
                                .foregroundStyle(DesignSystem.AppColors.secondaryText)
                            Text("You can close this screen. The download continues in the background.")
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
        .onChange(of: viewModel.didFinish) {
            if viewModel.didFinish { dismiss() }
        }
        .onChange(of: viewModel.urlText) {
            viewModel.errorMessage = nil
            viewModel.validateURL()
        }
    }
}
