@preconcurrency import AVFoundation
import Combine
import UIKit

/// Owns the capture session and every piece of state the UI renders.
///
/// Threading: all `@Published` state is mutated on the main actor. Anything that
/// touches `AVCaptureSession` configuration or `startRunning()`/`stopRunning()`
/// hops to `sessionQueue`, because those calls block.
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum SessionState: Equatable {
        case idle
        case unauthorized
        case running
        case failed(String)
    }

    // MARK: - Published state

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published private(set) var availableFlavors: [ProResFlavor] = []
    @Published private(set) var proResSupported = false
    @Published private(set) var appleLogSupported = false
    @Published private(set) var activeDimensions = CMVideoDimensions(width: 0, height: 0)
    @Published private(set) var activeFrameRate: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lenses: [Lens] = []
    @Published private(set) var activeLens: Lens?
    @Published private(set) var isSwitchingLens = false

    /// Selected by the UI. Changing either re-applies output settings.
    @Published var flavor: ProResFlavor = .standard {
        didSet { guard flavor != oldValue else { return }; applyOutputSettings() }
    }
    @Published var appleLogEnabled = false {
        didSet { guard appleLogEnabled != oldValue else { return }; applyColorSpace() }
    }

    // MARK: - Capture graph

    let session = AVCaptureSession()
    let manual: ManualControls

    private let sessionQueue: DispatchQueue
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?

    private var durationTimer: AnyCancellable?
    private var recordingStartedAt: Date?
    private let library = MediaLibrary()

    override init() {
        // Both the controller and the manual controls must serialise onto the same
        // queue — device locks and session reconfiguration cannot interleave.
        let queue = DispatchQueue(label: "com.logcam.session")
        sessionQueue = queue
        manual = ManualControls(sessionQueue: queue)
        super.init()
    }

    // MARK: - Lifecycle

    /// Requests permission, builds the graph, and starts the session.
    func start() async {
        guard sessionState != .running else { return }

        guard await requestAuthorization() else {
            sessionState = .unauthorized
            return
        }

        do {
            try await configureSession()
        } catch {
            sessionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            return
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }
        sessionState = .running

        if let videoDevice {
            manual.attach(to: videoDevice)
        }
    }

    /// Dismisses the error banner. Errors are non-fatal status, not alerts — the
    /// session keeps running underneath them.
    func clearError() {
        lastError = nil
    }

    func stop() {
        durationTimer?.cancel()
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        sessionState = .idle
    }

    private func requestAuthorization() async -> Bool {
        let video = await Self.authorize(for: .video)
        // Audio is desirable but not fatal — a silent ProRes clip still beats no clip.
        _ = await Self.authorize(for: .audio)
        return video
    }

    private static func authorize(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        default: return false
        }
    }

    // MARK: - Session configuration

    private enum ConfigurationError: LocalizedError {
        case noCamera
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noCamera: "No usable rear camera was found on this device."
            case .cannotAddInput: "The capture session rejected the camera input."
            case .cannotAddOutput: "The capture session rejected the movie output."
            }
        }
    }

    /// Builds the capture graph on `sessionQueue`, then publishes the resulting
    /// state back on the main actor.
    ///
    /// Nothing inside the queue block touches `@Published` state — the session is
    /// configured first, and only once it returns do we read capabilities off it.
    private func configureSession() async throws {
        let catalog = LensCatalog.discover()
        // Open on the wide lens when there is one — it is the only lens present on
        // every model, and the one users expect at launch.
        guard let startingLens = catalog.first(where: { $0.magnification >= 1 }) ?? catalog.first else {
            throw ConfigurationError.noCamera
        }
        let device = startingLens.device

        let input = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVCaptureDeviceInput, Error>) in
            sessionQueue.async { [session, movieOutput] in
                do {
                    session.beginConfiguration()

                    // `.inputPriority` is required so that our manual `activeFormat`
                    // choice is not overridden by a preset.
                    session.sessionPreset = .inputPriority

                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw ConfigurationError.cannotAddInput }
                    session.addInput(input)

                    if let mic = AVCaptureDevice.default(for: .audio),
                       let micInput = try? AVCaptureDeviceInput(device: mic),
                       session.canAddInput(micInput) {
                        session.addInput(micInput)
                    }

                    guard session.canAddOutput(movieOutput) else { throw ConfigurationError.cannotAddOutput }
                    session.addOutput(movieOutput)

                    try Self.selectBestFormat(on: device)

                    session.commitConfiguration()
                    continuation.resume(returning: input)
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }

        lenses = catalog
        activeLens = startingLens
        videoDevice = device
        videoInput = input
        refreshCapabilities()
        applyOutputSettings()
        // Assigning `activeFormat` resets `activeColorSpace`, so the colour space is
        // always re-applied after a format change — here and in `select(lens:)`.
        applyColorSpace()
        // Manual controls are attached in `start()`, once the session is actually
        // running — seeding the white-balance sliders reads the device's current
        // gains, which are not meaningful until frames are flowing.
    }

    // MARK: - Lens switching

    /// Swaps the session's video input to another physical lens.
    ///
    /// Blocked mid-recording: tearing the input out from under the file writer
    /// truncates the movie. The new lens gets its own format pick, so ProRes
    /// availability, resolution, and the manual exposure ranges are all re-read
    /// afterwards.
    func select(lens: Lens) async {
        guard lens != activeLens, !isRecording, !isSwitchingLens else { return }
        guard let currentInput = videoInput else { return }

        isSwitchingLens = true
        defer { isSwitchingLens = false }

        let device = lens.device

        let newInput = await withCheckedContinuation { (continuation: CheckedContinuation<AVCaptureDeviceInput?, Never>) in
            sessionQueue.async { [session] in
                session.beginConfiguration()
                session.removeInput(currentInput)

                guard let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    // Put the old lens back rather than leaving a session with no
                    // video input at all.
                    session.addInput(currentInput)
                    session.commitConfiguration()
                    continuation.resume(returning: nil)
                    return
                }

                session.addInput(input)
                try? Self.selectBestFormat(on: device)
                session.commitConfiguration()
                continuation.resume(returning: input)
            }
        }

        guard let newInput else {
            lastError = "Could not switch to the \(lens.displayName) lens."
            return
        }

        videoInput = newInput
        videoDevice = device
        activeLens = lens
        refreshCapabilities()
        applyOutputSettings()
        applyColorSpace()
        manual.attach(to: device)
    }

    /// Picks the highest-resolution format that can sustain 30fps, preferring one
    /// that can carry Apple Log.
    ///
    /// Two capabilities hang off the *active format*, not the device, so both are
    /// decided here:
    ///
    /// - ProRes availability, which is why this runs before we ask `movieOutput`
    ///   which codecs it supports.
    /// - Apple Log, which only ever exists on 10-bit formats. iPhones usually expose
    ///   both an 8-bit and a 10-bit variant at a given size, so resolution alone is
    ///   not enough to disambiguate — ranking on size *then* log support picks the
    ///   10-bit one without ever sacrificing resolution to get it. The 10-bit format
    ///   is the better ProRes base regardless of whether Log is switched on.
    nonisolated private static func selectBestFormat(on device: AVCaptureDevice) throws {
        let candidates = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }

        func rank(_ format: AVCaptureDevice.Format) -> (Int, Int) {
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let logCapable = format.supportedColorSpaces.contains(.appleLog) ? 1 : 0
            return (Int(size.width) * Int(size.height), logCapable)
        }

        guard let best = candidates.max(by: { rank($0) < rank($1) }) else { return }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = best
        let thirty = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = thirty
        device.activeVideoMaxFrameDuration = thirty
    }

    private func refreshCapabilities() {
        guard let device = videoDevice else { return }

        let format = device.activeFormat
        activeDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        activeFrameRate = 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        appleLogSupported = format.supportedColorSpaces.contains(.appleLog)

        let codecs = Set(movieOutput.availableVideoCodecTypes)
        availableFlavors = ProResFlavor.allCases.filter { codecs.contains($0.codec) }
        proResSupported = !availableFlavors.isEmpty

        if proResSupported, !availableFlavors.contains(flavor) {
            flavor = availableFlavors.contains(.standard) ? .standard : availableFlavors[0]
        }
        if !proResSupported {
            lastError = "This device does not support Apple ProRes capture. Recording will fall back to HEVC."
        }
    }

    /// Applies the selected codec to the live video connection.
    private func applyOutputSettings() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        let codec: AVVideoCodecType = proResSupported ? flavor.codec : .hevc
        sessionQueue.async { [movieOutput] in
            guard movieOutput.availableVideoCodecTypes.contains(codec) else { return }
            movieOutput.setOutputSettings([AVVideoCodecKey: codec], for: connection)
        }
    }

    private func applyColorSpace() {
        guard let device = videoDevice else { return }
        let target: AVCaptureColorSpace = appleLogEnabled ? .appleLog : .sRGB
        guard device.activeFormat.supportedColorSpaces.contains(target) else { return }

        sessionQueue.async { [session] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            // Only unlock if the lock actually succeeded — an unbalanced
            // unlockForConfiguration() traps.
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            device.activeColorSpace = target
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard sessionState == .running, !movieOutput.isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogCam-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        if let connection = movieOutput.connection(with: .video) {
            connection.videoRotationAngle = 90 // portrait
        }

        sessionQueue.async { [movieOutput, self] in
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        sessionQueue.async { [movieOutput] in
            movieOutput.stopRecording()
        }
    }

    private func beginDurationTimer() {
        recordedDuration = 0
        durationTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = recordingStartedAt else { return }
                recordedDuration = Date().timeIntervalSince(start)
            }
    }

    /// Bytes per second the current configuration is expected to consume.
    var estimatedBytesPerSecond: Double {
        guard activeDimensions.width > 0, activeFrameRate > 0 else { return 0 }
        let bits = flavor.estimatedBitsPerSecond(
            width: Int(activeDimensions.width),
            height: Int(activeDimensions.height),
            frameRate: activeFrameRate
        )
        return bits / 8
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraController: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            isRecording = true
            recordingStartedAt = Date()
            beginDurationTimer()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            isRecording = false
            durationTimer?.cancel()
            recordingStartedAt = nil
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

            if let error {
                lastError = error.localizedDescription
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }

            do {
                try await library.save(movieAt: outputFileURL)
            } catch {
                lastError = "Recorded, but saving to Photos failed: \(error.localizedDescription)"
            }
            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }
}
