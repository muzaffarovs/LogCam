import AVFoundation

/// One physical rear camera the app can switch to.
struct Lens: Identifiable, Equatable {
    let device: AVCaptureDevice
    /// Zoom multiple relative to the wide lens, e.g. 0.5, 1.0, 3.0.
    let magnification: Double

    var id: String { device.uniqueID }

    var displayName: String {
        // Trim "1.0×" to "1×" but keep "0.5×".
        let rounded = (magnification * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))×"
            : "\(rounded)×"
    }

    static func == (lhs: Lens, rhs: Lens) -> Bool { lhs.id == rhs.id }
}

/// Discovers the discrete rear cameras and labels them by zoom multiple.
///
/// This deliberately uses the *physical* devices rather than the virtual
/// `.builtInTripleCamera`. A virtual device switches lenses on its own by zoom
/// factor, which is smoother, but it also picks the format — and ProRes support
/// is a per-format property. Owning the device outright is what lets the app
/// guarantee a ProRes-capable format on every lens.
enum LensCatalog {

    static func discover() -> [Lens] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        let devices = discovery.devices
        guard let wide = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            // No wide lens to normalise against — fall back to unlabelled 1× entries.
            return devices.map { Lens(device: $0, magnification: 1) }
        }

        let wideFOV = Double(wide.activeFormat.videoFieldOfView)

        return devices
            .map { device -> Lens in
                // Field of view is inversely proportional to focal length, so the
                // ratio against the wide lens approximates the zoom multiple. This
                // is an estimate: Apple does not publish per-model zoom factors,
                // and they differ across iPhone generations (2×, 2.5×, 3×, 5×).
                let fov = Double(device.activeFormat.videoFieldOfView)
                let magnification = fov > 0 ? wideFOV / fov : 1
                return Lens(device: device, magnification: magnification)
            }
            .sorted { $0.magnification < $1.magnification }
    }
}
