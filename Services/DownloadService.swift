import Foundation

protocol DownloadServicing {
    func download(from url: URL) async throws -> URL
    func resumeDownload(from resumeData: Data, originalURL: URL) async throws -> URL
}

final class DownloadService: NSObject, DownloadServicing, URLSessionDownloadDelegate {
    static let shared = DownloadService()

    private let session: URLSession
    private let queue = DispatchQueue(label: "music.downloads")
    private var completionHandlers: [String: (Result<URL, Error>) -> Void] = [:]
    private var resumeDataByTask: [String: Data] = [:]
    private var taskIDs: [String: URLSessionDownloadTask] = [:]

    override init() {
        let config = URLSessionConfiguration.background(withIdentifier: "MusicDownloads")
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        super.init()
    }

    func download(from url: URL) async throws -> URL {
        let location: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
                guard let self else { return }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL, let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                let fileURL = try? self.storeDownloadedFile(from: tempURL, sourceURL: url)
                if let fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: URLError(.cannotCreateFile))
                }
            }
            task.resume()
        }
        return location
    }

    func resumeDownload(from resumeData: Data, originalURL: URL) async throws -> URL {
        let task = session.downloadTask(withResumeData: resumeData)
        let key = UUID().uuidString
        taskIDs[key] = task
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            completionHandlers[key] = { result in
                switch result {
                case .success(let url): continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskKey = taskIDs.first(where: { $0.value == downloadTask })?.key else { return }
        do {
            let destination = try storeDownloadedFile(from: location, sourceURL: downloadTask.originalRequest?.url ?? location)
            completionHandlers[taskKey]?(.success(destination))
        } catch {
            completionHandlers[taskKey]?(.failure(error))
        }
        completionHandlers.removeValue(forKey: taskKey)
        taskIDs.removeValue(forKey: taskKey)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskKey = taskIDs.first(where: { $0.value == task })?.key else { return }
        if let error {
            completionHandlers[taskKey]?(.failure(error))
        }
        completionHandlers.removeValue(forKey: taskKey)
        taskIDs.removeValue(forKey: taskKey)
    }

    private func storeDownloadedFile(from url: URL, sourceURL: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = sourceURL.lastPathComponent.isEmpty ? "downloaded-audio" : sourceURL.lastPathComponent
        let destination = documents.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
