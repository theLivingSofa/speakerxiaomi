#if os(macOS)
import EQCore
import SwiftUI

/// The overall EQ shape from 20 Hz to 20 kHz, preamp and speaker protection included.
struct ResponseCurveView: View {
    let settings: EQSettings

    private static let minFrequency = 20.0
    private static let maxFrequency = 20_000.0
    private static let dbRange = 15.0
    private static let sampleRate = 48_000.0

    var body: some View {
        Canvas { context, size in
            let gridColor = Color.secondary.opacity(0.2)

            // Grid: 0 / ±6 / ±12 dB, and 100 Hz, 1 kHz, 10 kHz.
            for db in [-12.0, -6, 0, 6, 12] {
                let y = Self.y(db, size)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(db == 0 ? Color.secondary.opacity(0.45) : gridColor), lineWidth: 1)
            }
            for (frequency, label) in [(100.0, "100"), (1000, "1k"), (10_000, "10k")] {
                let x = Self.x(frequency, size)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(gridColor), lineWidth: 1)
                context.draw(
                    Text(label).font(.system(size: 8)).foregroundColor(.secondary),
                    at: CGPoint(x: x + 3, y: size.height - 2),
                    anchor: .bottomLeading
                )
            }

            // Curve.
            var shown = settings
            shown.bypass = false
            let parameters = EQDesign.parameters(for: shown, sampleRate: Self.sampleRate)
            var curve = Path()
            let steps = 160
            for step in 0...steps {
                let frequency = Self.minFrequency * pow(Self.maxFrequency / Self.minFrequency, Double(step) / Double(steps))
                let db = settings.bypass
                    ? 0
                    : EQDesign.responseDB(of: parameters, at: frequency, sampleRate: Self.sampleRate)
                let point = CGPoint(x: Self.x(frequency, size), y: Self.y(db, size))
                if step == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            let style = settings.bypass
                ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                : StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            context.stroke(curve, with: .color(settings.bypass ? .secondary : .accentColor), style: style)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("EQ response curve")
    }

    private static func x(_ frequency: Double, _ size: CGSize) -> CGFloat {
        let t = log(frequency / minFrequency) / log(maxFrequency / minFrequency)
        return CGFloat(t) * size.width
    }

    private static func y(_ db: Double, _ size: CGSize) -> CGFloat {
        let clamped = min(max(db, -dbRange), dbRange)
        return CGFloat((dbRange - clamped) / (2 * dbRange)) * size.height
    }
}
#endif
