import Foundation
import Network

@MainActor
@Observable
final class ConnectivityService {
    var isOnline = true
    var isOfflineBannerVisible = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "music.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let next = path.status == .satisfied
                self?.isOnline = next
                if !next {
                    self?.isOfflineBannerVisible = true
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
