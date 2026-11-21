import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CounterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZikrActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.zSurface)
                .activitySystemActionForegroundColor(Color.zPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.stepTitle ?? context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.value, format: .number)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.zAccent)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let target = context.state.target {
                            ProgressView(value: Double(min(context.state.value, target)), total: Double(max(1, target)))
                                .tint(Color.zAccent)
                        }
                        Button(intent: LiveIncrementIntent(itemID: context.attributes.itemID)) {
                            Label(context.attributes.addLabel, systemImage: "plus")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.zAccent)
                    }
                }
            } compactLeading: {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Color.zAccent)
            } compactTrailing: {
                Text(context.state.value, format: .number).monospacedDigit()
            } minimal: {
                Text(context.state.value, format: .number).monospacedDigit().minimumScaleFactor(0.5)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ZikrActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                if let step = context.state.stepTitle, let position = context.state.stepPosition {
                    Text("\(position) · \(step)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(context.state.value, format: .number)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.zPrimary)
                        .contentTransition(.numericText(value: Double(context.state.value)))
                    if let target = context.state.target {
                        Text("/ \(target.formatted())").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if context.state.completed {
                    Label(context.attributes.doneLabel, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.zAccentText)
                } else {
                    Text("\(context.attributes.todayLabel): \(context.state.today.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(intent: LiveIncrementIntent(itemID: context.attributes.itemID)) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(Color.zPrimary)
            .accessibilityLabel(context.attributes.addLabel)
        }
        .padding(16)
    }
}
