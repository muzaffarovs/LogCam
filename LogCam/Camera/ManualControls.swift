import AVFoundation
import Combine

/// Manual focus, exposure (shutter + ISO), and white balance for the active camera.
///
/// Attach it to a device with `attach(to:)` whenever the lens or active format
/// changes — the legal ISO and shutter ranges are properties of the *format*, so
/// they must be re-read and the current values re-clamped after every switch.
@MainActor
final class ManualControls: ObservableObject {

    // MARK: - Focus

    @Published var autoFocus = true {
        didSet { guard autoFocus != oldValue else { return }; applyFocus() }
    }

    /// Lens position, 0.0 (closest) to 1.0 (infinity). The scale is unitless and
    /// deliberately not a distance — AVFoundation makes no promise that it is
    /// linear, or that a given value means the same thing across lenses.
    @Published var lensPosition: Float = 0.5 {
        didSet { guard !autoFocus else { return }; applyFocus() }
    }

    @Published private(set) var focusSupported = false

    // MARK: - Exposure

    /// When true the device runs continuous auto exposure and the sliders are inert.
    ///
    /// Shutter and ISO share one toggle because AVFoundation has no "manual shutter,
    /// auto ISO" mode: `setExposureModeCustom` takes both values in a single call,
    /// so leaving custom mode is all-or-nothing.
    @Published var autoExposure = true {
        didSet { guard autoExposure != oldValue else { return }; applyExposure() }
    }

    /// Normalised 0...1 slider position, mapped onto the duration range with a
    /// power curve so the fast end of the scale gets most of the travel.
    @Published var shutterPosition: Double = 0.5 {
        didSet { guard !autoExposure else { return }; applyExposure() }
    }

    @Published var iso: Float = 100 {
        didSet { guard !autoExposure else { return }; applyExposure() }
    }

    @Published private(set) var minISO: Float = 0
    @Published private(set) var maxISO: Float = 0
    @Published private(set) var exposureSupported = false

    // MARK: - White balance

    @Published var autoWhiteBalance = true {
        didSet { guard autoWhiteBalance != oldValue else { return }; applyWhiteBalance() }
    }

    @Published var temperature: Float = 5600 {
        didSet { guard !autoWhiteBalance else { return }; applyWhiteBalance() }
    }

    @Published var tint: Float = 0 {
        didSet { guard !autoWhiteBalance else { return }; applyWhiteBalance() }
    }

    @Published private(set) var whiteBalanceSupported = false

    static let temperatureRange: ClosedRange<Float> = 2000...10000
    static let tintRange: ClosedRange<Float> = -150...150

    // MARK: - Device binding

    private weak var device: AVCaptureDevice?
    private let sessionQueue: DispatchQueue

    /// Shortest duration the UI will offer. Formats often report microsecond
    /// minimums that are unusable in practice.
    private static let shortestOfferedDuration = 1.0 / 8000.0
    /// Longer than this and handheld video smears; also keeps the curve useful.
    private static let longestOfferedDuration = 1.0 / 8.0
    /// Biases slider travel toward fast shutter speeds, matching Apple's AVCam sample.
    private static let durationCurvePower = 5.0

    init(sessionQueue: DispatchQueue) {
        self.sessionQueue = sessionQueue
    }

    /// Re-reads capability ranges from the device's current format and re-applies
    /// whatever manual state the user had dialled in.
    func attach(to device: AVCaptureDevice) {
        self.device = device

        let format = device.activeFormat
        exposureSupported = device.isExposureModeSupported(.custom)
        whiteBalanceSupported = device.isWhiteBalanceModeSupported(.locked)
        // `.locked` alone only permits freezing focus where it already is. Driving
        // the lens to a chosen position needs the second capability too.
        focusSupported = device.isFocusModeSupported(.locked)
            && device.isLockingFocusWithCustomLensPositionSupported

        minISO = format.minISO
        maxISO = format.maxISO
        iso = min(max(iso, minISO), maxISO)

        if autoFocus {
            // Seed from wherever autofocus currently sits, so switching to manual
            // does not rack the lens.
            lensPosition = min(max(device.lensPosition, 0), 1)
        }

        if autoWhiteBalance {
            // Seed the sliders from what auto settled on, so flipping to manual
            // does not jump the image.
            let current = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            temperature = min(max(current.temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
            tint = min(max(current.tint, Self.tintRange.lowerBound), Self.tintRange.upperBound)
        }

        applyFocus()
        applyExposure()
        applyWhiteBalance()
    }

    // MARK: - Derived values

    /// Seconds of exposure for the current slider position.
    var shutterSeconds: Double {
        guard let device else { return 0 }
        let formatMin = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        let formatMax = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        let low = max(formatMin, Self.shortestOfferedDuration)
        let high = min(formatMax, Self.longestOfferedDuration)
        guard high > low else { return low }

        let curved = pow(min(max(shutterPosition, 0), 1), Self.durationCurvePower)
        return curved * (high - low) + low
    }

    /// Photographic label for the current shutter speed, e.g. "1/50".
    var shutterLabel: String {
        let seconds = shutterSeconds
        guard seconds > 0 else { return "—" }
        return "1/\(Int((1.0 / seconds).rounded()))"
    }

    /// Readout for the focus slider. The top of the range is the lens's infinity
    /// stop, so it earns the ∞ glyph rather than "1.00".
    var focusLabel: String {
        lensPosition >= 0.995 ? "∞" : String(format: "%.2f", lensPosition)
    }

    // MARK: - Application

    private func applyFocus() {
        guard let device, focusSupported else { return }

        if autoFocus {
            guard device.isFocusModeSupported(.continuousAutoFocus) else { return }
            perform(on: device) { $0.focusMode = .continuousAutoFocus }
            return
        }

        let position = min(max(lensPosition, 0), 1)
        perform(on: device) { device in
            device.setFocusModeLockedWithLensPosition(position, completionHandler: nil)
        }
    }

    private func applyExposure() {
        guard let device, exposureSupported else { return }

        if autoExposure {
            guard device.isExposureModeSupported(.continuousAutoExposure) else { return }
            perform(on: device) { $0.exposureMode = .continuousAutoExposure }
            return
        }

        let duration = CMTime(seconds: shutterSeconds, preferredTimescale: 1_000_000)
        let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)

        perform(on: device) { device in
            device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
        }
    }

    private func applyWhiteBalance() {
        guard let device, whiteBalanceSupported else { return }

        if autoWhiteBalance {
            guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
            perform(on: device) { $0.whiteBalanceMode = .continuousAutoWhiteBalance }
            return
        }

        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)

        perform(on: device) { device in
            // Converting temperature/tint can yield gains outside the device's legal
            // range; passing those to AVFoundation raises an exception rather than
            // failing softly, so clamp every channel first.
            let gains = Self.clamp(device.deviceWhiteBalanceGains(for: values), for: device)
            device.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(gains, completionHandler: nil)
        }
    }

    /// Recent SDKs nest the white-balance value types inside `AVCaptureDevice`;
    /// the old top-level `AVCaptureWhiteBalanceGains` spelling is now unavailable.
    private static func clamp(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let upper = device.maxWhiteBalanceGain
        func bound(_ value: Float) -> Float { min(max(value, 1.0), upper) }
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: bound(gains.redGain),
            greenGain: bound(gains.greenGain),
            blueGain: bound(gains.blueGain)
        )
    }

    /// Runs a configuration block on the session queue with the device lock held.
    private func perform(on device: AVCaptureDevice, _ body: @escaping (AVCaptureDevice) -> Void) {
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            body(device)
        }
    }
}
