import Foundation
import SwiftData

@MainActor
protocol DownloadServicing {
    /// Downloads the file and imports it into the library.
    func download(from url: URL) async throws -> [Track]
}

/// Background downloads: keep going while the app is suspended, report progress,
/// and import into the library when they finish (even if the app was relaunched in between).
@MainActor
final class DownloadService: NSObject, ObservableObject, DownloadServicing {
    static let shared = DownloadService()
    static let sessionIdentifier = "\(Bundle.main.bundleIdentifier ?? "Music").downloads"

    /// Download progress (0...1) keyed by source URL.
    @Published private(set) var progress: [URL: Double] = [:]

    /// Set by the app delegate when iOS wakes the app to finish background downloads.
    var backgroundCompletionHandler: (() -> Void)?

    private var waiters: [URL: CheckedContinuation<[Track], Error>] = [:]

    /// Recreates the background session so downloads finished while the app was gone get delivered.
    func reconnect() { _ = session }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.allowsConstrainedNetworkAccess = false
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // Delegate callbacks on the main queue so they can touch MainActor state directly.
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    func download(from url: URL) async throws -> [Track] {
        if waiters[url] != nil { throw URLError(.cancelled) }
        progress[url] = 0
        return try await withCheckedThrowingContinuation { continuation in
            waiters[url] = continuation
            let task = session.downloadTask(with: url)
            task.taskDescription = url.absoluteString
            task.resume()
        }
    }

    nonisolated static func fileExtension(forMIMEType mime: String?) -> String {
        switch mime?.lowercased() {
        case "audio/mp4", "audio/x-m4a", "audio/m4a": "m4a"
        case "audio/aac": "aac"
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/flac", "audio/x-flac": "flac"
        default: "mp3"
        }
    }

    /// Moves the temp file into Documents with a name and extension the library import accepts.
    nonisolated static func storeDownloadedFile(from tempURL: URL, response: URLResponse?, sourceURL: URL) throws -> URL {
        var name = response?.suggestedFilename ?? sourceURL.lastPathComponent
        if name.isEmpty { name = "downloaded-audio" }
        if !LibraryService.supportedExtensions.contains((name as NSString).pathExtension.lowercased()) {
            name += "." + fileExtension(forMIMEType: response?.mimeType)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var destination = documents.appendingPathComponent(name)
        // Never overwrite another track's audio.
        if FileManager.default.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            destination = documents.appendingPathComponent("\(base) \(UUID().uuidString.prefix(6))")
                .appendingPathExtension(destination.pathExtension)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func finish(_ sourceURL: URL, with result: Result<[Track], Error>) {
        progress[sourceURL] = nil
        waiters.removeValue(forKey: sourceURL)?.resume(with: result)
    }

    private func importDownloaded(_ file: URL, from sourceURL: URL) async {
        do {
            let tracks = try await LibraryService().importItems([file], into: MusicStore.context)
            for track in tracks {
                track.isDownloaded = true
                track.remoteURLString = sourceURL.absoluteString
            }
            try MusicStore.context.save()
            finish(sourceURL, with: .success(tracks))
        } catch {
            finish(sourceURL, with: .failure(error))
        }
    }
}

extension DownloadService: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let source = downloadTask.taskDescription.flatMap(URL.init(string:)) else { return }
        // The temp file is deleted when this method returns, so move it synchronously.
        let result: Result<URL, Error>
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            result = .failure(URLError(.badServerResponse))
        } else {
            result = Result { try Self.storeDownloadedFile(from: location, response: downloadTask.response, sourceURL: source) }
        }
        MainActor.assumeIsolated {
            switch result {
            case .success(let file): Task { await self.importDownloaded(file, from: source) }
            case .failure(let error): self.finish(source, with: .failure(error))
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0,
              let source = downloadTask.taskDescription.flatMap(URL.init(string:)) else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        MainActor.assumeIsolated { self.progress[source] = fraction }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let source = task.taskDescription.flatMap(URL.init(string:)) else { return }
        MainActor.assumeIsolated { self.finish(source, with: .failure(error)) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }
}
