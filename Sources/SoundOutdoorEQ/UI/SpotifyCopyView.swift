#if os(macOS)
import AppKit
import EQCore
import SwiftUI

/// Shows the current curve as Spotify's six iPhone EQ bands, so it can be copied onto the phone.
struct SpotifyCopyView: View {
    let settings: EQSettings
    let presetName: String?

    @State private var copied = false

    var body: some View {
        let gains = SpotifyEQ.gains(for: settings)
        VStack(alignment: .leading, spacing: 8) {
            Text("In Spotify on your iPhone, open Settings → Playback → Equalizer, turn it on, and drag the dots to match this shape.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SpotifyShape(gains: gains)
                .frame(height: 64)

            HStack(spacing: 0) {
                ForEach(SpotifyEQ.frequencies.indices, id: \.self) { index in
                    VStack(spacing: 1) {
                        Text(SpotifyEQ.gainLabel(gains[index]))
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Text(SpotifyEQ.frequencyLabel(SpotifyEQ.frequencies[index]))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(alignment: .top) {
                Button(copied ? "Copied" : "Copy Values") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(SpotifyEQ.summary(for: settings, presetName: presetName), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .controlSize(.small)
                .help("Copies the values as text. With Handoff on, you can paste them on your iPhone.")
                Text("Spotify's EQ has no limiter. If loud songs crackle, lower all six dots a little.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Six evenly spaced dots joined by a line, laid out like Spotify's equalizer.
private struct SpotifyShape: View {
    let gains: [Int]

    var body: some View {
        Canvas { context, size in
            let range = Double(SpotifyEQ.range.upperBound)
            let inset: CGFloat = 10
            let width = size.width - inset * 2
            let height = size.height - inset * 2
            func point(_ index: Int) -> CGPoint {
                let x = inset + width * CGFloat(index) / CGFloat(max(gains.count - 1, 1))
                let y = inset + height * CGFloat((range - Double(gains[index])) / (2 * range))
                return CGPoint(x: x, y: y)
            }

            var zero = Path()
            zero.move(to: CGPoint(x: inset, y: size.height / 2))
            zero.addLine(to: CGPoint(x: size.width - inset, y: size.height / 2))
            context.stroke(zero, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            guard !gains.isEmpty else { return }
            var line = Path()
            line.move(to: point(0))
            for index in gains.indices.dropFirst() {
                line.addLine(to: point(index))
            }
            context.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for index in gains.indices {
                let p = point(index)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.green), lineWidth: 2)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .accessibilityLabel("Spotify equalizer shape")
    }
}
#endif
