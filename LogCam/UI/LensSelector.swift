import SwiftUI

/// Horizontal lens pills, mimicking the stock Camera app's zoom selector.
struct LensSelector: View {
    @ObservedObject var camera: CameraController

    var body: some View {
        HStack(spacing: 4) {
            ForEach(camera.lenses) { lens in
                let selected = camera.activeLens == lens
                Button {
                    Task { await camera.select(lens: lens) }
                } label: {
                    Text(lens.displayName)
                        .font(.system(size: selected ? 15 : 13, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .yellow : .white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(selected ? 0.22 : 0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(lens.displayName) lens")
            }
        }
        .padding(4)
        .background(.black.opacity(0.3), in: Capsule())
        .disabled(camera.isRecording || camera.isSwitchingLens)
        .opacity(camera.isRecording ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: camera.activeLens)
    }
}
