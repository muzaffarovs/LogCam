import AVFoundation

/// The ProRes variants LogCam exposes, ordered lightest to heaviest.
///
/// Apple ProRes capture is only available on iPhone 13 Pro and later, and only
/// when the active device format supports it — see `CameraController.refreshAvailableFlavors()`.
enum ProResFlavor: String, CaseIterable, Identifiable, Sendable {
    case proxy
    case lt
    case standard
    case hq

    var id: String { rawValue }

    var codec: AVVideoCodecType {
        switch self {
        case .proxy: .proRes422Proxy
        case .lt: .proRes422LT
        case .standard: .proRes422
        case .hq: .proRes422HQ
        }
    }

    var displayName: String {
        switch self {
        case .proxy: "422 Proxy"
        case .lt: "422 LT"
        case .standard: "422"
        case .hq: "422 HQ"
        }
    }

    /// Published Apple data rate at 1920x1080 / 29.97fps, in megabits per second.
    /// Used as the reference point for `bitrate(width:height:frameRate:)`.
    private var referenceMegabitsPerSecond: Double {
        switch self {
        case .proxy: 45
        case .lt: 102
        case .standard: 147
        case .hq: 220
        }
    }

    private static let referencePixelsPerSecond = 1920.0 * 1080.0 * 29.97

    /// Estimated sustained bitrate in bits per second for a given capture geometry.
    ///
    /// ProRes is a constant-quality codec, so real files vary with scene detail.
    /// This scales the published 1080p figure by pixels-per-second, which is close
    /// enough to drive a "time remaining" readout but is not exact.
    func estimatedBitsPerSecond(width: Int, height: Int, frameRate: Double) -> Double {
        let pixelsPerSecond = Double(width) * Double(height) * frameRate
        let scale = pixelsPerSecond / Self.referencePixelsPerSecond
        return referenceMegabitsPerSecond * 1_000_000 * scale
    }
}
