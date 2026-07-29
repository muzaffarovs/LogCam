import SwiftUI

/// Collapsible drawer of manual exposure and white-balance controls.
///
/// Manual settings stay live during a take — unlike codec and lens, changing
/// shutter, ISO, or white balance mid-recording is safe and is something
/// operators genuinely want.
struct ManualControlPanel: View {
    @ObservedObject var manual: ManualControls
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 14) {
            header

            if expanded {
                VStack(spacing: 16) {
                    if manual.focusSupported { focusSection }
                    if manual.exposureSupported { exposureSection }
                    if manual.whiteBalanceSupported { whiteBalanceSection }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                Text(summary)
                    .font(.caption.monospacedDigit())
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    /// One-line state readout so the panel is useful while collapsed.
    private var summary: String {
        let focus = manual.autoFocus ? "AF" : "MF \(manual.focusLabel)"
        let exposure = manual.autoExposure
            ? "AE"
            : "\(manual.shutterLabel) · ISO \(Int(manual.iso))"
        let balance = manual.autoWhiteBalance ? "AWB" : "\(Int(manual.temperature))K"
        return "\(focus)   \(exposure)   \(balance)"
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(spacing: 10) {
            SectionHeader(
                title: "Focus",
                autoLabel: "Auto",
                isAuto: $manual.autoFocus
            )

            SliderRow(
                label: "Lens",
                value: Binding(
                    get: { Double(manual.lensPosition) },
                    set: { manual.lensPosition = Float($0) }
                ),
                range: 0...1,
                readout: manual.focusLabel,
                disabled: manual.autoFocus
            )
        }
    }

    // MARK: - Exposure

    private var exposureSection: some View {
        VStack(spacing: 10) {
            SectionHeader(
                title: "Exposure",
                autoLabel: "Auto",
                isAuto: $manual.autoExposure
            )

            SliderRow(
                label: "Shutter",
                value: $manual.shutterPosition,
                range: 0...1,
                readout: manual.shutterLabel,
                disabled: manual.autoExposure
            )

            SliderRow(
                label: "ISO",
                value: Binding(
                    get: { Double(manual.iso) },
                    set: { manual.iso = Float($0) }
                ),
                range: Double(manual.minISO)...Double(max(manual.maxISO, manual.minISO + 1)),
                readout: "\(Int(manual.iso))",
                disabled: manual.autoExposure
            )
        }
    }

    // MARK: - White balance

    private var whiteBalanceSection: some View {
        VStack(spacing: 10) {
            SectionHeader(
                title: "White Balance",
                autoLabel: "Auto",
                isAuto: $manual.autoWhiteBalance
            )

            SliderRow(
                label: "Temp",
                value: Binding(
                    get: { Double(manual.temperature) },
                    set: { manual.temperature = Float($0) }
                ),
                range: Double(ManualControls.temperatureRange.lowerBound)
                    ...Double(ManualControls.temperatureRange.upperBound),
                readout: "\(Int(manual.temperature))K",
                disabled: manual.autoWhiteBalance
            )

            SliderRow(
                label: "Tint",
                value: Binding(
                    get: { Double(manual.tint) },
                    set: { manual.tint = Float($0) }
                ),
                range: Double(ManualControls.tintRange.lowerBound)
                    ...Double(ManualControls.tintRange.upperBound),
                readout: "\(Int(manual.tint))",
                disabled: manual.autoWhiteBalance
            )
        }
    }
}

// MARK: - Pieces

private struct SectionHeader: View {
    let title: String
    let autoLabel: String
    @Binding var isAuto: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button(autoLabel) {
                isAuto.toggle()
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(isAuto ? .black : .white)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(isAuto ? .yellow : .white.opacity(0.15), in: Capsule())
            .buttonStyle(.plain)
        }
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: String
    let disabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 48, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(.yellow)

            Text(readout)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 56, alignment: .trailing)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}
