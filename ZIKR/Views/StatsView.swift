import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @State private var scope: ItemRef?
    @State private var range = 7

    var body: some View {
        let _ = store.dayRefresh
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scopePicker
                    let daily = Stats.daily(store.data, ref: scope)
                    let overall = Stats.overallDaily(store.data)
                    tiles(daily: daily, overall: overall)
                    HeatmapCard(daily: daily)
                    chart(daily: daily)
                    if let scope, scope.kind == .counter, let counter = store.data.counter(scope.id), !counter.journal.isEmpty {
                        journal(counter)
                    }
                    Text(store.t("stats.footnote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.zBackground.ignoresSafeArea())
            .navigationTitle(store.t("tab.stats"))
        }
    }

    private var scopePicker: some View {
        Menu {
            Button {
                scope = nil
            } label: {
                Label(store.t("stats.all"), systemImage: scope == nil ? "checkmark" : "square.stack")
            }
            Divider()
            ForEach(store.rows()) { row in
                Button {
                    scope = row.ref
                } label: {
                    Label(row.title, systemImage: scope == row.ref ? "checkmark" : store.icon(for: row.ref))
                }
            }
        } label: {
            HStack {
                Text(scope.flatMap { store.data.title(of: $0) } ?? store.t("stats.all"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.subheadline)
            }
            .padding(14)
            .background(Color.zSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(Color.zPrimary)
        .accessibilityLabel(store.t("stats.scopeA11y"))
    }

    @ViewBuilder
    private func tiles(daily: [String: Int], overall: [String: Int]) -> some View {
        let today = daily[DayKey.key(Date())] ?? 0
        let week = Stats.sum(daily, lastDays: 7)
        let streak = Stats.softStreak(activeDays: Set(daily.keys))
        let activeDays = daily.count
        let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: grid, spacing: 10) {
            StatTile(value: store.num(today), label: store.t("stats.today"), icon: "sun.max")
            StatTile(value: store.num(week), label: store.t("stats.week"), icon: "calendar")
            StatTile(value: store.p("unit.days", streak), label: store.t("stats.streak"), icon: "flame")
            StatTile(value: store.num(activeDays), label: store.t("stats.activeDays"), icon: "checkmark.circle")
            if let scope, scope.kind == .program, let program = store.data.program(scope.id) {
                StatTile(value: store.num(program.totalCompletions), label: store.t("stats.completions"), icon: "checkmark.seal")
            } else if let scope, scope.kind == .counter, let counter = store.data.counter(scope.id) {
                StatTile(value: store.num(counter.value), label: store.t("stats.total"), icon: "sum")
            } else {
                StatTile(value: store.num(overall.values.reduce(0, +)), label: store.t("stats.allTaps"), icon: "sum")
            }
            StatTile(value: L10n.duration(Stats.seconds(store.data, ref: scope)), label: store.t("stats.time"), icon: "stopwatch")
        }
        Text(store.t("stats.streakNote"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func chart(daily: [String: Int]) -> some View {
        let days: [DayValue] = (0..<range).reversed().map { offset in
            let date = DayKey.shifted(Date(), days: -offset)
            let key = DayKey.key(date)
            return DayValue(date: date, key: key, value: daily[key] ?? 0)
        }
        let total = days.reduce(0) { $0 + $1.value }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.t("stats.byDay")).font(.headline)
                    Spacer()
                    Text(store.num(total)).font(.headline).foregroundStyle(Color.zPrimary)
                }
                Picker(store.t("stats.period"), selection: $range) {
                    Text(store.t("stats.7days")).tag(7)
                    Text(store.t("stats.30days")).tag(30)
                }
                .pickerStyle(.segmented)
                Chart(days) { day in
                    BarMark(x: .value(store.t("stats.day"), day.date, unit: .day),
                            y: .value(store.t("stats.taps"), day.value))
                        .foregroundStyle(Color.zPrimary.gradient)
                        .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: range == 7 ? .dateTime.weekday(.narrow) : .dateTime.day().month(.defaultDigits))
                    }
                }
                .environment(\.locale, store.locale)
                .frame(height: 180)
            }
        }
    }

    private func journal(_ counter: Counter) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("stats.corrections")).font(.headline)
                ForEach(counter.journal.suffix(10).reversed()) { entry in
                    HStack {
                        Text(entry.at.formatted(.dateTime.day().month().hour().minute().locale(store.locale)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.kind == .baseline
                             ? store.f("stats.baseline", store.num(entry.after))
                             : "\(store.num(entry.before)) → \(store.num(entry.after))")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }
}

struct DayValue: Identifiable {
    var date: Date
    var key: String
    var value: Int
    var id: String { key }
}

/// GitHub-style activity grid for the last 26 weeks.
struct HeatmapCard: View {
    @Environment(AppStore.self) private var store
    let daily: [String: Int]
    private let weeks = 26

    var body: some View {
        let calendar = DayKey.calendar()
        let today = Date()
        // Align columns to weeks ending today.
        let todayWeekday = calendar.component(.weekday, from: today)
        let firstWeekday = L10n.orderedWeekdays(store.language).first ?? 2
        let rowOfToday = (todayWeekday - firstWeekday + 7) % 7
        let maxValue = max(1, daily.values.max() ?? 1)
        let activeInRange = (0..<(weeks * 7)).filter { daily[DayKey.key(DayKey.shifted(today, days: -$0))] != nil }.count

        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.t("stats.heatmap")).font(.headline)
                    Spacer()
                    Text(store.p("unit.days", activeInRange)).font(.subheadline).foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    let spacing: CGFloat = 3
                    let cell = max(4, (proxy.size.width - spacing * CGFloat(weeks - 1)) / CGFloat(weeks))
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<weeks, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    let offset = (weeks - 1 - column) * 7 + (rowOfToday - row)
                                    let value = offset >= 0 ? (daily[DayKey.key(DayKey.shifted(today, days: -offset))] ?? 0) : -1
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(value: value, max: maxValue))
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .aspectRatio(CGFloat(weeks) / 7, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.t("stats.heatmap"))
                .accessibilityValue(store.p("unit.days", activeInRange))
                HStack(spacing: 4) {
                    Text(store.t("stats.less")).font(.caption2).foregroundStyle(.secondary)
                    ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level == 0 ? Color.zBeadDim : Color.zBead.opacity(0.25 + 0.1875 * Double(level)))
                            .frame(width: 10, height: 10)
                    }
                    Text(store.t("stats.more")).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func color(value: Int, max: Int) -> Color {
        if value < 0 { return .clear }
        if value == 0 { return Color.zBeadDim }
        let level = Double(value) / Double(max)
        return Color.zBead.opacity(0.35 + 0.65 * level)
    }
}
