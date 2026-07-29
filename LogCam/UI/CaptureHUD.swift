import SwiftUI

/// Top-of-frame readout: recording clock, capture geometry, and remaining storage.
struct CaptureHUD: View {
    @ObservedObject var camera: CameraController
    @ObservedObject var storage: StorageMonitor

    private var resolutionText: String {
        guard camera.activeDimensions.width > 0 else { return "—" }
        return "\(camera.activeDimensions.width)×\(camera.activeDimensions.height)"
    }

    private var remainingText: String {
        guard let seconds = storage.remainingSeconds(atBytesPerSecond: camera.estimatedBytesPerSecond) else {
            return Formatters.bytes(storage.availableBytes)
        }
        return "\(Formatters.compactDuration(seconds)) left"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(camera.isRecording ? 1 : 0)

                Text(Formatters.duration(camera.recordedDuration))
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .foregroundStyle(camera.isRecording ? .red : .white)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                Label(resolutionText, systemImage: "rectangle.expand.vertical")
                Label("\(Int(camera.activeFrameRate.rounded()))fps", systemImage: "timelapse")
                Label(remainingText, systemImage: "internaldrive")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.black.opacity(0.35), in: Capsule())
        .animation(.default, value: camera.isRecording)
    }
}
