#if os(macOS)
import EQCore
import SwiftUI

/// Ten vertical band sliders. Double-click a slider to reset it to 0 dB.
struct EQSlidersView: View {
    @Binding var gains: [Double]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(EQSettings.bandFrequencies.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(Self.gainLabel(gains[index]))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(gains[index] == 0 ? Color.secondary : Color.primary)
                    VerticalSlider(value: binding(for: index), range: EQSettings.gainRange)
                        .frame(height: 120)
                    Text(Self.frequencyLabel(EQSettings.bandFrequencies[index]))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(Self.frequencyLabel(EQSettings.bandFrequencies[index]))Hz: \(Self.gainLabel(gains[index])) dB")
            }
        }
    }

    private func binding(for index: Int) -> Binding<Double> {
        Binding(
            get: { gains.indices.contains(index) ? gains[index] : 0 },
            set: { newValue in
                guard gains.indices.contains(index), gains[index] != newValue else { return }
                gains[index] = newValue
            }
        )
    }

    static func frequencyLabel(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }

    static func gainLabel(_ gain: Double) -> String {
        let rounded = (gain * 2).rounded() / 2
        if rounded == 0 { return "0" }
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return rounded > 0 ? "+\(text)" : text
    }
}

/// A vertical slider in 0.5 dB steps, with a center line at 0.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let usable = max(height - thumb, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let thumbY = usable * (1 - fraction)
            let zeroY = usable * (1 - (0 - range.lowerBound) / span)
            let centerX = geo.size.width / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 4, height: height)
                    .offset(x: centerX - 2)
                Rectangle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 12, height: 1)
                    .offset(x: centerX - 6, y: zeroY + thumb / 2)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: abs(thumbY - zeroY))
                    .offset(x: centerX - 2, y: min(thumbY, zeroY) + thumb / 2)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: thumb, height: thumb)
                    .offset(x: centerX - thumb / 2, y: thumbY)
            }
            .frame(width: geo.size.width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = 1 - (drag.location.y - thumb / 2) / usable
                    let raw = range.lowerBound + min(max(Double(f), 0), 1) * span
                    value = (raw * 2).rounded() / 2
                }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}
#endif
