import Foundation

enum Formatters {

    /// Timecode-style elapsed clock, e.g. "00:04:12".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Compact "time remaining" for the storage readout, e.g. "8m" or "1h 12m".
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}
