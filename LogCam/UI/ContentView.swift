import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var storage = StorageMonitor()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.sessionState {
            case .running:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            case .unauthorized:
                MessageView(
                    symbol: "camera.metering.unknown",
                    title: "Camera access needed",
                    message: "Enable camera access for LogCam in Settings → Privacy → Camera."
                )
            case .failed(let reason):
                MessageView(symbol: "exclamationmark.triangle", title: "Camera unavailable", message: reason)
            case .idle:
                ProgressView().tint(.white)
            }

            if camera.sessionState == .running {
                controls
            }

            if let message = camera.lastError {
                ErrorBanner(message: message) { camera.clearError() }
            }
        }
        .task {
            await camera.start()
            storage.startMonitoring()
        }
        .onDisappear {
            storage.stopMonitoring()
            camera.stop()
        }
    }

    private var controls: some View {
        VStack {
            CaptureHUD(camera: camera, storage: storage)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                ManualControlPanel(manual: camera.manual)

                HStack(spacing: 10) {
                    if camera.proResSupported {
                        flavorPicker
                    }
                    if camera.appleLogSupported {
                        logToggle
                    }
                }

                if camera.lenses.count > 1 {
                    LensSelector(camera: camera)
                }

                RecordButton(
                    isRecording: camera.isRecording,
                    isEnabled: camera.sessionState == .running
                ) {
                    camera.toggleRecording()
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    /// Codec choice is locked mid-take — swapping output settings while the file
    /// writer is running would corrupt the movie.
    private var flavorPicker: some View {
        HStack(spacing: 6) {
            ForEach(camera.availableFlavors) { flavor in
                let selected = camera.flavor == flavor
                Button(flavor.displayName) {
                    camera.flavor = flavor
                }
                .font(.caption.weight(selected ? .bold : .regular))
                .foregroundStyle(selected ? .black : .white)
                .padding(.vertical, 7)
                .padding(.horizontal, 13)
                .background(selected ? .white : .white.opacity(0.15), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .disabled(camera.isRecording)
        .opacity(camera.isRecording ? 0.4 : 1)
    }

    private var logToggle: some View {
        Toggle("Apple Log", isOn: $camera.appleLogEnabled)
            .toggleStyle(.button)
            .font(.caption.weight(.medium))
            .tint(.yellow)
            .disabled(camera.isRecording)
            .opacity(camera.isRecording ? 0.4 : 1)
    }
}

/// Non-fatal status, shown in-frame because there is no attached debugger to read.
/// Sits above the HUD and stays until tapped, so a failure during a take is still
/// legible afterwards.
private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .onTapGesture(perform: dismiss)

            Spacer()
        }
        .padding(.top, 90)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct MessageView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(40)
    }
}
