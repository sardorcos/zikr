import SwiftUI

/// The big tap target: a ring of 33 beads that fills as the current cycle progresses.
struct CounterFace: View {
    @Environment(AppStore.self) private var store
    let status: ItemStatus
    /// Position inside the current cycle and the cycle length (interval, step target or 33).
    let cyclePosition: Int
    let cycleLength: Int
    let onTap: @MainActor () -> Void
    let onUndo: @MainActor () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 76
    private let beadCount = 33

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let filled = cycleLength > 0 ? min(beadCount, Int((Double(cyclePosition) / Double(cycleLength) * Double(beadCount)).rounded(.down))) : 0
            Button(action: onTap) {
                ZStack {
                    ForEach(0..<beadCount, id: \.self) { index in
                        let angle = Double(index) / Double(beadCount) * 2 * .pi - .pi / 2
                        Circle()
                            .fill(index < filled ? Color.zBead : (index == filled ? Color.zAccent : Color.zBeadDim))
                            .frame(width: size * 0.082, height: size * 0.082)
                            .offset(x: cos(angle) * size * 0.44, y: sin(angle) * size * 0.44)
                    }
                    VStack(spacing: 4) {
                        if let step = status.stepTitle {
                            Text(step)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        Text(store.num(status.value))
                            .font(.system(size: numberSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.zPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .contentTransition(.numericText(value: Double(status.value)))
                        if let target = status.target {
                            Text(store.f("face.outOf", store.num(target)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: size * 0.66)
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
            }
            .buttonStyle(FacePressStyle())
            .animation(.snappy(duration: 0.18), value: status.value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.stepTitle.map { "\(status.title), \($0)" } ?? status.title)
            .accessibilityValue(status.target.map { store.f("face.a11yValueOf", store.num(status.value), store.num($0)) }
                                ?? store.num(status.value))
            .accessibilityHint(store.t("face.a11yHint"))
            .accessibilityAddTraits([.isButton, .updatesFrequently])
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onTap()
                case .decrement: onUndo()
                @unknown default: break
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
    }
}

private struct FacePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
