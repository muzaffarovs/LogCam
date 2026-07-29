import AVFoundation
import SwiftUI
import UIKit

/// Hosts the capture session's preview layer.
///
/// Backing the `UIView` with `AVCaptureVideoPreviewLayer` as its `layerClass` keeps
/// the layer sized by UIKit's layout pass — no manual frame bookkeeping, and no
/// stutter when the device rotates.
final class PreviewBackedView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewBackedView {
        let view = PreviewBackedView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewBackedView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}
