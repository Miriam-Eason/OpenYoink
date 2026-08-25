import SwiftUI

struct IslandBatteryView: View {
    @Environment(PowerSourceMonitor.self) private var powerMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            IslandModuleHeader(
                title: "Battery",
                subtitle: nil,
                systemImage: batterySymbol
            )
            if powerMonitor.snapshot.hasBattery {
                VStack(spacing: 12) {
                    HStack(spacing: 20) {
                        BatteryChargeRing(
                            percentage: powerMonitor.snapshot.percentage,
                            tint: batteryTint,
                            reduceMotion: reduceMotion
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                Image(systemName: statusSymbol)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(batteryTint)
                                    .frame(width: 28, height: 28)
                                    .background {
                                        Circle().fill(batteryTint.opacity(0.13))
                                    }

                                Text(powerStatus)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(IslandVisualStyle.primaryText)
                                    .lineLimit(1)
                            }

                            if let powerWatts = powerMonitor.snapshot.powerWatts {
                                let formattedPower = BatteryPowerFormatting.string(watts: powerWatts)
                                Text(formattedPower)
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(IslandVisualStyle.primaryText)
                                    .contentTransition(.numericText())
                                    .accessibilityLabel(Text("Battery power"))
                                    .accessibilityValue(Text(formattedPower))
                            } else {
                                Text("Not Available")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(IslandVisualStyle.tertiaryText)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    Divider()
                        .overlay(IslandVisualStyle.hairline)

                    BatteryPowerWaveform(
                        samples: powerMonitor.powerHistory,
                        currentWatts: powerMonitor.snapshot.powerWatts
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(batteryCardBackground)
            } else {
                IslandEmptyState(
                    title: "Not applicable",
                    message: "This Mac does not report an internal battery.",
                    systemImage: "desktopcomputer"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var batteryCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(IslandVisualStyle.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(IslandVisualStyle.hairline, lineWidth: 1)
            }
    }

    private var statusSymbol: String {
        if powerMonitor.snapshot.isCharging { return "bolt.fill" }
        if powerMonitor.snapshot.isConnectedToPower { return "powerplug.fill" }
        return batterySymbol
    }

    private var batterySymbol: String {
        switch powerMonitor.snapshot.percentage {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...65: return "battery.50percent"
        case 66...90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryTint: Color {
        if powerMonitor.snapshot.percentage <= 10 { return .red }
        if powerMonitor.snapshot.percentage <= 20 { return .orange }
        return .green
    }

    private var powerStatus: String {
        if powerMonitor.snapshot.isCharging { return String(localized: "Charging") }
        if powerMonitor.snapshot.isConnectedToPower { return String(localized: "Connected to power") }
        return String(localized: "Running on battery")
    }
}
private struct BatteryChargeRing: View {
    let percentage: Int
    let tint: Color
    let reduceMotion: Bool

    private var progress: Double {
        min(max(Double(percentage) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: 8)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.62), tint, tint.opacity(0.88)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.30), radius: 5)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35),
                           value: progress)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percentage)")
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandVisualStyle.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandVisualStyle.secondaryText)
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text("\(percentage) percent"))
    }
}

private struct BatteryPowerWaveform: View {
    let samples: [BatteryPowerSample]
    let currentWatts: Double?

    private var scaleWatts: Double {
        let maximum = samples.map { abs($0.watts) }.max() ?? abs(currentWatts ?? 0)
        return max(10, ceil(maximum * 1.15 / 5) * 5)
    }

    private var averageWatts: Double? {
        guard !samples.isEmpty else { return currentWatts }
        return samples.map(\.watts).reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Label("Power history", systemImage: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandVisualStyle.secondaryText)

                Spacer(minLength: 8)

                if let averageWatts {
                    HStack(spacing: 3) {
                        Text("Average")
                        Text(BatteryPowerFormatting.string(watts: averageWatts))
                            .monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandVisualStyle.tertiaryText)
                }

                Text("2 min")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandVisualStyle.tertiaryText)
            }

            BatteryPowerCanvas(samples: samples, scaleWatts: scaleWatts)
                .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 82)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Power history"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let currentWatts else { return String(localized: "Not Available") }
        return BatteryPowerFormatting.string(watts: currentWatts)
    }
}

private struct BatteryPowerCanvas: View {
    let samples: [BatteryPowerSample]
    let scaleWatts: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let axisWidth: CGFloat = 36
            let plot = CGRect(x: axisWidth, y: 5,
                              width: max(0, size.width - axisWidth - 1),
                              height: max(0, size.height - 10))
            guard plot.width > 0, plot.height > 0 else { return }

            let zeroY = plot.midY
            drawGrid(in: plot, zeroY: zeroY, context: &context)
            guard !samples.isEmpty else { return }

            let points = samplePoints(in: plot, zeroY: zeroY)
            guard !points.isEmpty else { return }

            if points.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: points[0].x, y: zeroY))
                area.addLine(to: points[0])
                for point in points.dropFirst() {
                    area.addLine(to: point)
                }
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: zeroY))
                area.closeSubpath()

                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.green.opacity(0.24),
                            Color.green.opacity(0.02),
                            Color.cyan.opacity(0.02),
                            Color.cyan.opacity(0.22),
                        ]),
                        startPoint: CGPoint(x: plot.midX, y: plot.minY),
                        endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                    )
                )

                var line = Path()
                line.move(to: points[0])
                for point in points.dropFirst() {
                    line.addLine(to: point)
                }
                context.stroke(
                    line,
                    with: .linearGradient(
                        Gradient(colors: [.green, .mint, .cyan]),
                        startPoint: CGPoint(x: plot.midX, y: plot.minY),
                        endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            if let latest = points.last {
                let dot = Path(ellipseIn: CGRect(x: latest.x - 3.25,
                                                y: latest.y - 3.25,
                                                width: 6.5, height: 6.5))
                let tint: Color = (samples.last?.watts ?? 0) >= 0 ? .green : .cyan
                context.fill(dot, with: .color(tint))
                context.stroke(dot, with: .color(.white.opacity(0.72)), lineWidth: 1)
            }
        }
        .overlay(alignment: .topLeading) {
            Text(BatteryPowerFormatting.string(watts: scaleWatts))
                .offset(y: -2)
        }
        .overlay(alignment: .bottomLeading) {
            Text(BatteryPowerFormatting.string(watts: -scaleWatts))
                .offset(y: 2)
        }
        .overlay(alignment: .leading) {
            Text("0 W")
        }
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(IslandVisualStyle.tertiaryText)
    }

    private func drawGrid(
        in plot: CGRect,
        zeroY: CGFloat,
        context: inout GraphicsContext
    ) {
        for fraction in [0.25, 0.5, 0.75] {
            let x = plot.minX + plot.width * fraction
            var line = Path()
            line.move(to: CGPoint(x: x, y: plot.minY))
            line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }

        var zeroLine = Path()
        zeroLine.move(to: CGPoint(x: plot.minX, y: zeroY))
        zeroLine.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
        context.stroke(
            zeroLine,
            with: .color(.white.opacity(0.15)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
        )
    }

    private func samplePoints(in plot: CGRect, zeroY: CGFloat) -> [CGPoint] {
        guard let newest = samples.last?.timestamp else { return [] }
        let oldest = newest.addingTimeInterval(-PowerSourceMonitor.powerHistoryDuration)
        let verticalRange = plot.height / 2 - 3

        return samples.map { sample in
            let elapsed = sample.timestamp.timeIntervalSince(oldest)
            let progress = min(max(elapsed / PowerSourceMonitor.powerHistoryDuration, 0), 1)
            let normalizedWatts = min(max(sample.watts / scaleWatts, -1), 1)
            return CGPoint(
                x: plot.minX + plot.width * CGFloat(progress),
                y: zeroY - verticalRange * CGFloat(normalizedWatts)
            )
        }
    }
}
