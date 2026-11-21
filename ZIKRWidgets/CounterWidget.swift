import AppIntents
import SwiftUI
import WidgetKit

struct CounterEntry: TimelineEntry {
    let date: Date
    let status: ItemStatus?
    let language: AppLanguage
    /// The counter chosen in the widget settings (nil = follow the current one). Passed to the
    /// buttons so they change the item the widget shows.
    let item: ItemEntity?

    static let sample = CounterEntry(
        date: .now,
        status: ItemStatus(ref: .counter(UUID()), title: "ZIKR", value: 33, target: 100, today: 33,
                           stepPosition: nil, stepTitle: nil),
        language: .preferred(),
        item: nil)
}

struct CounterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CounterEntry { .sample }

    func snapshot(for configuration: SelectItemIntent, in context: Context) async -> CounterEntry {
        makeEntry(configuration, fallbackToSample: true)
    }

    func timeline(for configuration: SelectItemIntent, in context: Context) async -> Timeline<CounterEntry> {
        // Refresh right after midnight so "today" resets even if nothing is tapped.
        let midnight = Calendar.current.startOfDay(for: DayKey.shifted(Date(), days: 1)).addingTimeInterval(60)
        return Timeline(entries: [makeEntry(configuration, fallbackToSample: false)], policy: .after(midnight))
    }

    private func makeEntry(_ configuration: SelectItemIntent, fallbackToSample: Bool) -> CounterEntry {
        let data = DataFile.shared.peek()
        let language = data?.settings.language ?? .preferred()
        // A chosen item that was archived or deleted falls back to the current one.
        var chosen = configuration.item
        if let ref = chosen?.ref, let data, !data.isLive(ref) { chosen = nil }
        let status = data.flatMap { Actions.status($0, ref: chosen?.ref) }
        if status == nil && fallbackToSample { return .sample }
        return CounterEntry(date: .now, status: status, language: language, item: chosen)
    }
}

struct CounterWidget: Widget {
    static let kind = "ZIKRCounterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectItemIntent.self, provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
                .containerBackground(Color.zSurface, for: .widget)
        }
        .configurationDisplayName(Text(L10n.t("widget.name", .preferred())))
        .description(Text(L10n.t("widget.description", .preferred())))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CounterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CounterEntry

    private func t(_ key: String) -> String { L10n.t(key, entry.language) }
    private func num(_ value: Int) -> String { L10n.number(value, entry.language) }

    var body: some View {
        if let status = entry.status {
            switch family {
            case .accessoryCircular: circular(status)
            case .accessoryRectangular: rectangular(status)
            case .accessoryInline: Text("\(status.title) · \(num(status.value))")
            case .systemMedium: medium(status)
            default: small(status)
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid").font(.title2).foregroundStyle(Color.zPrimary)
            Text(t("widget.empty")).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private func small(_ status: ItemStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.stepTitle ?? status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(num(status.value))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.zPrimary)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(status.value)))
            if let fraction = status.fraction {
                ProgressView(value: fraction).tint(Color.zAccent)
            } else {
                Text("\(t("common.today")): \(num(status.today))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(intent: IncrementIntent(item: entry.item)) {
                Label(t("live.add"), systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.zPrimary)
        }
    }

    private func medium(_ status: ItemStatus) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.zBeadDim, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: status.fraction ?? 0)
                    .stroke(Color.zPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(num(status.value))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.zPrimary)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(10)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(status.title).font(.headline).lineLimit(1)
                if let step = status.stepTitle, let position = status.stepPosition {
                    Text("\(position) · \(step)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(t("common.today")): \(num(status.today))").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(intent: UndoIntent(item: entry.item)) {
                        Image(systemName: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(intent: IncrementIntent(item: entry.item)) {
                        Label(t("live.add"), systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .tint(Color.zPrimary)
            }
        }
    }

    private func circular(_ status: ItemStatus) -> some View {
        Button(intent: IncrementIntent(item: entry.item)) {
            ZStack {
                AccessoryWidgetBackground()
                if let fraction = status.fraction {
                    Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                        Text(num(status.value)).minimumScaleFactor(0.4)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    VStack(spacing: 0) {
                        Image(systemName: "plus").font(.caption2)
                        Text(num(status.value)).font(.headline).minimumScaleFactor(0.4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }

    private func rectangular(_ status: ItemStatus) -> some View {
        Button(intent: IncrementIntent(item: entry.item)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(status.stepTitle ?? status.title).font(.headline).lineLimit(1).widgetAccentable()
                Text(status.target.map { "\(num(status.value)) / \(num($0))" } ?? num(status.value))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
                Text("\(t("common.today")): \(num(status.today))").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
