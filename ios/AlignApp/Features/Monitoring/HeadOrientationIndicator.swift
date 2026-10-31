import SwiftUI

/// A top-down 2D view of head tilt relative to the neutral baseline: the marker moves down for
/// forward tilt (chin toward chest), up for looking up, and sideways for lateral tilt. The
/// dashed outline is the reminder threshold. Shape and text, not just color, show whether the
/// head is outside the range.
struct HeadOrientationIndicator: View {
    var forwardDegrees: Double?
    var lateralDegrees: Double?
    var forwardThreshold: Double
    var backwardThreshold: Double
    var lateralThreshold: Double
    var isOutsideRange: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markerSize: CGFloat = 36

    /// Degrees at the outer ring: twice the largest threshold.
    private var displayRange: Double {
        max(forwardThreshold, backwardThreshold, lateralThreshold, 5) * 2
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            ZStack {
                Circle()
                    .fill(Theme.cardBackground)
                Circle()
                    .stroke(Theme.hairline, lineWidth: 1)
                Crosshair()
                    .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                ThresholdOutline(
                    forwardFraction: CGFloat(forwardThreshold / displayRange),
                    backwardFraction: CGFloat(backwardThreshold / displayRange),
                    lateralFraction: CGFloat(lateralThreshold / displayRange)
                )
                .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                edgeLabels(radius: radius)
                if let offset = markerOffset(radius: radius) {
                    marker
                        .offset(offset)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: offset)
                }
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Head orientation")
        .accessibilityValue(accessibilityValue)
    }

    private var marker: some View {
        ZStack {
            if isOutsideRange {
                Circle()
                    .fill(Theme.caution)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
            } else {
                Circle()
                    .fill(Theme.accent)
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                    .padding(6)
            }
        }
        .frame(width: markerSize, height: markerSize)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    private func edgeLabels(radius: CGFloat) -> some View {
        let inset = radius - 14
        return ZStack {
            Text("Up").offset(y: -inset)
            Text("Down").offset(y: inset)
            Text("L").offset(x: -inset)
            Text("R").offset(x: inset)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func markerOffset(radius: CGFloat) -> CGSize? {
        guard let forward = forwardDegrees, let lateral = lateralDegrees else { return nil }
        var x = lateral / displayRange
        var y = forward / displayRange
        let length = (x * x + y * y).squareRoot()
        if length > 1 {
            x /= length
            y /= length
        }
        let travel = Double(max(0, radius - markerSize / 2))
        return CGSize(width: x * travel, height: y * travel)
    }

    private var accessibilityValue: String {
        guard let forward = forwardDegrees, let lateral = lateralDegrees else {
            return "No tilt data"
        }
        let range = isOutsideRange ? "Outside your range" : "Within your range"
        return "\(Format.spokenTilt(forward: forward, lateral: lateral)). \(range)."
    }
}

/// Threshold outline: an ellipse-like curve whose lower half uses the forward threshold, upper
/// half the backward threshold and horizontal extent the lateral threshold. Fractions are
/// relative to the view's half-size.
struct ThresholdOutline: Shape {
    var forwardFraction: CGFloat
    var backwardFraction: CGFloat
    var lateralFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let half = min(rect.width, rect.height) / 2
        let steps = 120
        for index in 0...steps {
            let theta = Double(index) / Double(steps) * 2 * Double.pi
            let cosine = CGFloat(cos(theta))
            let sine = CGFloat(sin(theta))
            // Screen y grows downward, so positive sine is the forward (chin-down) half.
            let verticalFraction = sine >= 0 ? forwardFraction : backwardFraction
            let point = CGPoint(
                x: rect.midX + lateralFraction * half * cosine,
                y: rect.midY + verticalFraction * half * sine
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Horizontal and vertical center lines.
struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#Preview("Indicator") {
    VStack(spacing: 24) {
        HeadOrientationIndicator(forwardDegrees: 6, lateralDegrees: -3, forwardThreshold: 15, backwardThreshold: 20, lateralThreshold: 15, isOutsideRange: false)
        HeadOrientationIndicator(forwardDegrees: 22, lateralDegrees: 4, forwardThreshold: 15, backwardThreshold: 20, lateralThreshold: 15, isOutsideRange: true)
    }
    .padding()
}
