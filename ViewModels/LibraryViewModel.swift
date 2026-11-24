import Foundation
import SwiftData

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    private let libraryService: any LibraryServicing

    init(libraryService: any LibraryServicing) {
        self.libraryService = libraryService
    }

    convenience init() {
        self.init(libraryService: LibraryService())
    }

    func importItems(_ urls: [URL], into context: ModelContext) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await libraryService.importItems(urls, into: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
