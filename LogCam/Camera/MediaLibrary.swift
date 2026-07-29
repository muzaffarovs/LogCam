import Photos

/// Moves finished recordings into the user's Photos library.
///
/// ProRes clips are large, so this deliberately uses `shouldMoveFile = true`:
/// Photos takes ownership of the temp file instead of duplicating gigabytes.
struct MediaLibrary {

    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "LogCam is not allowed to add videos to your photo library."
            }
        }
    }

    func save(movieAt url: URL) async throws {
        guard await requestAddAuthorization() else { throw SaveError.notAuthorized }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }

    private func requestAddAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }
}
