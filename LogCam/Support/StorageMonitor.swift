import Foundation

/// Reports free disk space so the HUD can show how much ProRes footage still fits.
///
/// ProRes 422 HQ at 4K burns roughly a gigabyte every ten seconds, so this is a
/// headline number rather than a nicety.
@MainActor
final class StorageMonitor: ObservableObject {

    @Published private(set) var availableBytes: Int64 = 0

    private var timer: Timer?

    init() {
        refresh()
    }

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        availableBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Seconds of recording left at the supplied sustained byte rate.
    func remainingSeconds(atBytesPerSecond rate: Double) -> TimeInterval? {
        guard rate > 0, availableBytes > 0 else { return nil }
        return Double(availableBytes) / rate
    }
}
