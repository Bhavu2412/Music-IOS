import Foundation

@MainActor
@Observable
final class SleepTimerService {
    static let shared = SleepTimerService()

    var isEnabled = false
    var remainingSeconds: TimeInterval = 0
    private var timer: Timer?

    func start(minutes: Int) {
        stop()
        let seconds = max(1, minutes * 60)
        remainingSeconds = TimeInterval(seconds)
        isEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.stop()
                    PlaybackService.shared.pausePlayback()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        remainingSeconds = 0
    }
}
