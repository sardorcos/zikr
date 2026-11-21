import SwiftUI

struct CounterScreen: View {
    @Environment(WatchModel.self) private var model
    @State private var banner: String?

    var body: some View {
        let lang = model.language
        Group {
            if let item = model.current {
                counter(item, lang: lang)
            } else {
                ContentUnavailableView {
                    Label(WatchText.t("empty.title", lang), systemImage: "circle.dotted")
                } description: {
                    Text(WatchText.t("empty.body", lang))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ItemsList()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel(WatchText.t("list", lang))
                .disabled(!model.hasData)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel(WatchText.t("undo", lang))
                .disabled(model.current.map { !model.canUndo($0) } ?? true)
            }
        }
        .onChange(of: model.milestoneToken) { _, _ in
            let key: String? = switch model.lastMilestone {
            case .none: nil
            case .interval: "milestone.interval"
            case .goal: "milestone.goal"
            case .step: "milestone.step"
            case .programCompleted: "milestone.done"
            }
            guard let key else { return }
            withAnimation { banner = WatchText.t(key, lang) }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation { banner = nil }
            }
        }
    }

    private func counter(_ item: WatchItem, lang: String) -> some View {
        let target = targetFor(item)
        return Button {
            model.tap()
        } label: {
            VStack(spacing: 2) {
                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.kind == .program, !item.steps.isEmpty {
                    let index = min(item.stepIndex, item.steps.count - 1)
                    Text(item.steps[index].title.isEmpty ? WatchText.f("step", lang, "\(index + 1)") : item.steps[index].title)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.gold)
                        .lineLimit(1)
                }
                ZStack {
                    Circle()
                        .stroke(WatchTheme.primary.opacity(0.18), lineWidth: 6)
                    if let target, target > 0 {
                        Circle()
                            .trim(from: 0, to: min(1, Double(progressValue(item)) / Double(target)))
                            .stroke(WatchTheme.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy, value: item.value)
                    }
                    VStack(spacing: 0) {
                        Text(WatchText.number(item.value, lang))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText(value: Double(item.value)))
                        if let target {
                            Text(WatchText.f("of", lang, WatchText.number(target, lang)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                }
                .padding(.horizontal, 14)
                .overlay(alignment: .bottom) {
                    if let banner {
                        Text(banner)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(WatchTheme.primary, in: Capsule())
                            .foregroundStyle(.black)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                Text(model.unsyncedCount > 0
                     ? WatchText.f("unsynced", lang, "\(model.unsyncedCount)")
                     : WatchText.f("today", lang, WatchText.number(item.today, lang)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Double tap (Apple Watch Series 9 / Ultra 2 and later) counts without touching the screen.
        .handGestureShortcut(.primaryAction)
        .accessibilityLabel(item.title)
        .accessibilityValue(WatchText.number(item.value, lang))
        .accessibilityHint(WatchText.t("a11y.add", lang))
    }

    private func targetFor(_ item: WatchItem) -> Int? {
        switch item.kind {
        case .counter:
            if let interval = item.interval, interval > 0 { return interval }
            return item.goal
        case .program:
            guard !item.steps.isEmpty else { return nil }
            return item.steps[min(item.stepIndex, item.steps.count - 1)].target
        }
    }

    /// Progress inside the ring: within the current round for interval counters.
    private func progressValue(_ item: WatchItem) -> Int {
        if item.kind == .counter, let interval = item.interval, interval > 0 {
            let r = item.value % interval
            return r == 0 && item.value > 0 ? interval : r
        }
        return item.value
    }
}

struct ItemsList: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let lang = model.language
        let items = model.items
        List {
            section(WatchText.t("list", lang), items.filter { $0.kind == .counter }, lang: lang)
            section(WatchText.t("programs", lang), items.filter { $0.kind == .program }, lang: lang)
        }
        .navigationTitle(WatchText.t("list", lang))
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [WatchItem], lang: String) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Button {
                        model.select(item.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1)
                                Text(WatchText.number(item.value, lang))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if item.id == model.current?.id {
                                Image(systemName: "checkmark").foregroundStyle(WatchTheme.primary)
                            }
                        }
                    }
                }
            }
        }
    }
}
