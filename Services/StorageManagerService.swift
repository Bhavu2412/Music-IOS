import Foundation

protocol StorageManaging {
    func documentsUsage() -> Int64
    func cachedUsage() -> Int64
    func clearCache() throws
}

final class StorageManagerService: StorageManaging {
    func documentsUsage() -> Int64 {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return totalSize(at: docsURL)
    }

    func cachedUsage() -> Int64 {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return totalSize(at: cacheURL)
    }

    func clearCache() throws {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let contents = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        for url in contents {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func totalSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
