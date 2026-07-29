import SwiftUI

/// The classic camera shutter: a white ring around a red core that morphs from
/// circle to rounded square while recording.
struct RecordButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 30, style: .continuous)
                    .fill(.red)
                    .frame(
                        width: isRecording ? 32 : 60,
                        height: isRecording ? 32 : 60
                    )
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
