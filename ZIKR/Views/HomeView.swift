import SwiftUI

enum EditorSheet: Identifiable {
    case newCounter
    case newProgram
    case editCounter(UUID)
    case editProgram(UUID)
    case correct(UUID)
    case reminder(ItemRef)

    var id: String {
        switch self {
        case .newCounter: return "newCounter"
        case .newProgram: return "newProgram"
        case .editCounter(let id): return "editCounter-\(id)"
        case .editProgram(let id): return "editProgram-\(id)"
        case .correct(let id): return "correct-\(id)"
        case .reminder(let ref): return "reminder-\(ref.storageString)"
        }
    }
}

struct EditorSheetContent: View {
    let sheet: EditorSheet

    var body: some View {
        Group {
            switch sheet {
            case .newCounter: CounterEditor(counterID: nil)
            case .newProgram: ProgramEditor(programID: nil)
            case .editCounter(let id): CounterEditor(counterID: id)
            case .editProgram(let id): ProgramEditor(programID: id)
            case .correct(let id): CorrectionSheet(counterID: id)
            case .reminder(let ref): ReminderSheet(ref: ref)
            }
        }
        .storeAlert()
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: EditorSheet?
    @State private var confirmArchive = false
    @State private var confirmRestart = false

    var body: some View {
        @Bindable var store = store
        // Read so "today" refreshes at midnight while the screen is open.
        let _ = store.dayRefresh
        NavigationStack {
            Group {
                if let ref = store.activeRef, let status = store.activeStatus {
                    content(ref: ref, status: status)
                } else {
                    emptyState
                }
            }
            .background(Color.zBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(item: $sheet) { EditorSheetContent(sheet: $0) }
        .fullScreenCover(isPresented: $store.nightModePresented) { NightModeView() }
        .confirmationDialog(store.t("home.archiveConfirm"), isPresented: $confirmArchive, titleVisibility: .visible) {
            Button(store.t("action.archive"), role: .destructive) {
                if let ref = store.activeRef { store.archive(ref) }
            }
            Button(store.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(store.t("home.archiveMessage"))
        }
        .confirmationDialog(store.t("home.restartConfirm"), isPresented: $confirmRestart, titleVisibility: .visible) {
            Button(store.t("action.restart"), role: .destructive) {
                if let ref = store.activeRef, ref.kind == .program { store.restartProgram(id: ref.id) }
            }
            Button(store.t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(ref: ItemRef, status: ItemStatus) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if ref.kind == .program, let program = store.data.program(ref.id) {
                    programHeader(program)
                }
                CounterFace(status: status,
                            cyclePosition: cycle(ref: ref, status: status).position,
                            cycleLength: cycle(ref: ref, status: status).length,
                            onTap: store.tap,
                            onUndo: store.undo)
                    .padding(.horizontal, 8)
                progressInfo(ref: ref, status: status)
                actionRow(ref: ref)
                StopwatchCard(ref: ref)
                if let note = note(ref), !note.isEmpty {
                    Card {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func cycle(ref: ItemRef, status: ItemStatus) -> (position: Int, length: Int) {
        switch ref.kind {
        case .program:
            return (status.value, status.target ?? 33)
        case .counter:
            let length = max(1, store.data.counter(ref.id)?.interval ?? 33)
            return (status.value % length, length)
        }
    }

    private func note(_ ref: ItemRef) -> String? {
        switch ref.kind {
        case .counter: return store.data.counter(ref.id)?.note
        case .program: return store.data.program(ref.id)?.note
        }
    }

    private func programHeader(_ program: Program) -> some View {
        let session = program.session ?? ProgramSession()
        let index = min(session.stepIndex, program.steps.count - 1)
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(program.steps.enumerated()), id: \.element.id) { offset, _ in
                    Capsule()
                        .fill(offset < index ? Color.zBead : (offset == index ? Color.zAccent : Color.zBeadDim))
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text(store.f("program.stepOf", store.num(index + 1), store.num(program.steps.count)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.zPrimary)
                Spacer()
                if index + 1 < program.steps.count {
                    Text(store.f("program.next", program.steps[index + 1].title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func progressInfo(ref: ItemRef, status: ItemStatus) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(store.f("home.today", store.num(status.today)), systemImage: "sun.max")
                Spacer()
                switch ref.kind {
                case .counter:
                    if let counter = store.data.counter(ref.id), let interval = counter.interval, interval > 0 {
                        Text(store.f("home.rounds", store.num(counter.value / interval)))
                    }
                case .program:
                    if let program = store.data.program(ref.id) {
                        Text(store.f("home.completedToday", store.num(program.completions[DayKey.key(Date())] ?? 0)))
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if ref.kind == .counter, let counter = store.data.counter(ref.id) {
                if let daily = counter.dailyGoal {
                    goalBar(label: store.f("home.dailyGoal", store.num(status.today), store.num(daily)),
                            value: Double(min(status.today, daily)), total: Double(daily), done: status.today >= daily)
                }
                if let goal = counter.goal {
                    goalBar(label: store.f("home.totalGoal", percent(counter.value, goal)),
                            value: Double(min(counter.value, goal)), total: Double(goal), done: counter.value >= goal)
                }
            }
        }
    }

    private func percent(_ value: Int, _ total: Int) -> String {
        (Double(value) / Double(max(1, total))).formatted(.percent.precision(.fractionLength(0...1)).locale(store.locale))
    }

    private func goalBar(label: String, value: Double, total: Double, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.zAccent)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            ProgressView(value: value, total: max(1, total))
                .tint(done ? Color.zAccent : Color.zPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionRow(ref: ItemRef) -> some View {
        HStack(spacing: 10) {
            actionButton(store.t("action.undo"), icon: "arrow.uturn.backward", enabled: store.canUndo(ref)) {
                store.undo()
            }
            actionButton(store.t("action.night"), icon: "moon.fill") {
                store.nightModePresented = true
            }
            actionButton(store.liveActivityRef == ref ? store.t("action.lockScreenOn") : store.t("action.lockScreen"),
                         icon: store.liveActivityRef == ref ? "lock.fill" : "lock") {
                store.toggleLiveActivity()
            }
        }
    }

    private func actionButton(_ title: String, icon: String, enabled: Bool = true, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .tint(Color.zPrimary)
        .disabled(!enabled)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.t("home.emptyTitle"), systemImage: "circle.hexagongrid")
        } description: {
            Text(store.t("home.emptyBody"))
        } actions: {
            Button(store.t("action.newCounter")) { sheet = .newCounter }
                .buttonStyle(.borderedProminent)
            Button(store.t("action.newProgram")) { sheet = .newProgram }
                .buttonStyle(.bordered)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if store.hasItems { itemSwitcher }
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { sheet = .newCounter } label: { Label(store.t("action.newCounter"), systemImage: "circle.circle") }
                Button { sheet = .newProgram } label: { Label(store.t("action.newProgram"), systemImage: "list.number") }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(store.t("action.create"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let ref = store.activeRef { itemMenu(ref) }
        }
    }

    private var itemSwitcher: some View {
        Menu {
            ForEach(store.rows()) { row in
                Button {
                    store.select(row.ref)
                } label: {
                    Label(row.title, systemImage: row.ref == store.activeRef ? "checkmark" : store.icon(for: row.ref))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.activeStatus?.title ?? "ZIKR")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(store.f("home.switchA11y", store.activeStatus?.title ?? ""))
    }

    private func itemMenu(_ ref: ItemRef) -> some View {
        let pinned = ref.kind == .counter ? (store.data.counter(ref.id)?.pinned ?? false) : (store.data.program(ref.id)?.pinned ?? false)
        return Menu {
            switch ref.kind {
            case .counter:
                Button { sheet = .editCounter(ref.id) } label: { Label(store.t("action.edit"), systemImage: "pencil") }
                Button { sheet = .correct(ref.id) } label: { Label(store.t("action.correct"), systemImage: "number") }
            case .program:
                Button { sheet = .editProgram(ref.id) } label: { Label(store.t("action.edit"), systemImage: "pencil") }
                Button { confirmRestart = true } label: { Label(store.t("action.restart"), systemImage: "arrow.counterclockwise") }
            }
            Button { sheet = .reminder(ref) } label: { Label(store.t("action.reminder"), systemImage: "bell") }
            Button { store.togglePin(ref) } label: {
                Label(pinned ? store.t("action.unpin") : store.t("action.pin"), systemImage: pinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive) { confirmArchive = true } label: {
                Label(store.t("action.archive"), systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(store.t("action.more"))
    }
}

struct StopwatchCard: View {
    @Environment(AppStore.self) private var store
    let ref: ItemRef

    var body: some View {
        let running = store.timerRef == ref
        Card {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .foregroundStyle(Color.zPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("timer.title")).font(.subheadline.weight(.medium))
                    Text(store.t("timer.hint")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(L10n.duration(store.elapsed(at: context.date)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Button(running ? store.t("timer.pause") : store.t("timer.start")) {
                    if running { store.pauseTimer() } else { store.startTimer() }
                }
                .buttonStyle(.bordered)
                .tint(Color.zPrimary)
            }
        }
    }
}
