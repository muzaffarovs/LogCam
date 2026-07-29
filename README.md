# LogCam

A minimal iPhone camera app that records Apple ProRes video, with codec choice,
Apple Log, and a storage-aware HUD.

## Requirements

- **Xcode 16+** — the project uses a file-system-synchronized group, so new files
  dropped into `LogCam/` are picked up without editing the project file.
- **iOS 17+** deployment target (`AVCaptureConnection.videoRotationAngle` and
  `AVCaptureColorSpace.appleLog` are both 17.0 APIs).
- **A physical iPhone 13 Pro or later.** ProRes capture does not exist in the
  Simulator, and non-Pro iPhones have no ProRes encoder. On unsupported hardware
  the app degrades to HEVC and says so.

## Running

```sh
open LogCam.xcodeproj
```

Set your signing team on the `LogCam` target (it ships with
`DEVELOPMENT_TEAM` blank), then run on a connected device.

If you are on Xcode 15 or the project file gets damaged:

```sh
brew install xcodegen
rm -rf LogCam.xcodeproj && xcodegen
```

## Layout

| Folder | Contents |
| --- | --- |
| `Camera/` | `CameraController` (capture graph, recording, lens switching), `ProResFlavor` (codec table + bitrate math), `LensCatalog` (rear lens discovery), `ManualControls` (shutter/ISO/WB), `MediaLibrary` (Photos save) |
| `Render/` | `CameraPreviewView` — `AVCaptureVideoPreviewLayer` bridged into SwiftUI |
| `UI/` | `ContentView`, `RecordButton`, `CaptureHUD`, `LensSelector`, `ManualControlPanel` |
| `Support/` | App entry point, `StorageMonitor`, `Formatters` |

## How ProRes selection works

ProRes availability is a property of the **active device format**, not the device,
so the order in `CameraController` matters:

1. `session.sessionPreset = .inputPriority` — otherwise a preset overrides the
   manual format choice.
2. Pick the largest format that sustains 30fps, assign `device.activeFormat`.
3. Ask `movieOutput.availableVideoCodecTypes` which ProRes variants survived.
4. Apply the chosen codec with `setOutputSettings(_:for:)` on the video connection.

Codec swaps are blocked mid-recording — changing output settings while the file
writer is running corrupts the movie.

## Apple Log

This is genuine Apple Log — `device.activeColorSpace = .appleLog`, the real iOS 17
API — not a LUT or a simulated log *look*. The sensor records the Apple Log transfer
function.

Apple Log only exists on **10-bit** formats, and iPhones expose both 8-bit and 10-bit
variants at the same resolution. `selectBestFormat` therefore ranks formats by size
*then* by log capability, so the 10-bit variant wins without giving up resolution. Rank
on resolution alone and the picker lands on an 8-bit format at random, `appleLogSupported`
reads false, and the toggle silently never appears on hardware that fully supports it.

Assigning `activeFormat` resets `activeColorSpace`, so the colour space is re-applied
after every format change, including lens switches.

**Unverified on device:** the interaction between Apple Log and
`automaticallyAdjustsVideoHDREnabled`. Apple Log formats are 10-bit HDR-capable, and
automatic HDR adjustment may fight the colour-space assignment. If Log engages but the
image looks wrong, that is the first thing to investigate.

Finished clips are handed to Photos with `shouldMoveFile = true` so multi-gigabyte
takes are not duplicated on disk.

## Lenses and manual control

`LensCatalog` discovers the **discrete physical** rear cameras (ultra-wide, wide,
telephoto) rather than the virtual `.builtInTripleCamera`. A virtual device switches
lenses itself by zoom factor and picks its own format — but ProRes support is a
per-format property, so owning each device outright is what lets the app guarantee a
ProRes-capable format on every lens. The cost is a visible hitch on switch, since the
session input is genuinely swapped.

Lens labels (`0.5×`, `1×`, `3×`) are derived by comparing each lens's field of view
against the wide lens. Apple does not publish per-model zoom factors and they vary by
generation, so these are estimates.

Manual controls live in `ManualControls`, applied on the same serial queue as session
configuration so device locks and reconfiguration cannot interleave:

- **Manual focus** drives `setFocusModeLockedWithLensPosition`, gated on *both*
  `isFocusModeSupported(.locked)` and `isLockingFocusWithCustomLensPositionSupported` —
  `.locked` alone only permits freezing focus where it already is. Lens position is a
  unitless 0…1 (closest → infinity), not a distance: AVFoundation does not promise the
  scale is linear or consistent across lenses.
- **Shutter and ISO share one Auto toggle.** AVFoundation has no "manual shutter, auto
  ISO" mode — `setExposureModeCustom(duration:iso:)` takes both in a single call, so
  leaving auto exposure is all-or-nothing.
- The shutter slider is mapped through a power curve (`pow(position, 5)`), giving most
  of the travel to fast speeds, as in Apple's AVCam sample.
- White balance converts temperature/tint to RGB gains, then **clamps every channel** to
  `[1.0, device.maxWhiteBalanceGain]`. Out-of-range gains raise an exception rather than
  failing softly.
- ISO and shutter ranges come from the *active format*, so they are re-read and
  re-clamped after every lens switch.
- Every manual slider seeds from whatever the automatic mode had settled on, so
  flipping a control to manual never jumps the image.

Lens switching is blocked mid-recording (swapping the input truncates the movie), but
focus, shutter, ISO, and white balance all stay live during a take.

## Shipping checklist

Not App Store ready. Outstanding:

- **App icon.** There is no asset catalog at all; App Store Connect rejects builds
  without a 1024×1024 icon.
- **Signing.** `DEVELOPMENT_TEAM` is blank and `com.logcam.LogCam` is a
  placeholder bundle ID that has not been registered.
- **App name.** "ProRes" is an Apple trademark. Apple's guidelines permit truthful
  compatibility references ("shoots ProRes") but not building their mark into a
  product name. Expect the *App Store* name to need changing — the Xcode target can
  stay as-is.
- **Non-Pro hardware.** ProRes needs iPhone 13 Pro or later, and there is no
  `UIRequiredDeviceCapabilities` key for it, so App Store availability cannot be
  limited to Pro models. Review may well test on a base iPhone. The HEVC fallback path
  therefore has to be genuinely good, not a stub — it is the app a reviewer might see.
- **App Store Connect metadata:** screenshots, description, category, age rating,
  privacy policy URL, and privacy nutrition labels (this app collects nothing).

Done:

- `PrivacyInfo.xcprivacy` declares the disk-space required-reason API that
  `StorageMonitor` uses (`E174.1` — displaying disk space to the user). Required since
  2024; uploads that touch a required-reason API without it are rejected.
- `ITSAppUsesNonExemptEncryption = NO` pre-answers export compliance. **Verify this key
  actually lands in the built `Info.plist`** — it is set via `INFOPLIST_KEY_`, and if it
  does not appear, answer the export question manually in App Store Connect instead.
- All three usage-description strings (camera, microphone, photo library) are present.

## Known gaps

- Rear cameras only — no front camera.
- No tap-to-focus or focus peaking; focus is slider-only.
- The remaining-time estimate scales Apple's published 1080p data rates by
  pixels-per-second. ProRes is constant-quality, so real files vary with scene detail.
- No app icon or launch asset catalog.
- Recording is portrait-locked.
