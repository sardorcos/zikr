import SwiftUI

struct CounterEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let counterID: UUID?

    @State private var title = ""
    @State private var initial = ""
    @State private var hasGoal = false
    @State private var goal = ""
    @State private var interval = "33"
    @State private var dailyGoal = ""
    @State private var note = ""
    @State private var errorText: String?
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { counterID == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("editor.titlePlaceholder"), text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($titleFocused)
                        .onChange(of: title) { _, value in
                            if value.count > Limits.titleLength { title = String(value.prefix(Limits.titleLength)) }
                        }
                    if isNew {
                        NumberField(title: store.t("editor.initial"), text: $initial, placeholder: "0")
                    }
                } header: {
                    Text(store.t("editor.title"))
                } footer: {
                    if isNew { Text(store.t("editor.initialFooter")) }
                }

                Section {
                    Toggle(store.t("editor.hasGoal"), isOn: $hasGoal.animation())
                    if hasGoal {
                        NumberField(title: store.t("editor.goal"), text: $goal, placeholder: "1000")
                    }
                    NumberField(title: store.t("editor.dailyGoal"), text: $dailyGoal, placeholder: store.t("editor.optional"))
                } header: {
                    Text(store.t("editor.goals"))
                }

                Section {
                    NumberField(title: store.t("editor.interval"), text: $interval, placeholder: store.t("editor.optional"))
                } footer: {
                    Text(store.t("editor.intervalFooter"))
                }

                Section(store.t("editor.note")) {
                    TextField(store.t("editor.notePlaceholder"), text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? store.t("action.newCounter") : store.t("editor.editCounter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("common.save"), action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = counterID, let c = store.data.counter(id) else {
            titleFocused = true
            return
        }
        title = c.title
        hasGoal = c.goal != nil
        goal = c.goal.map(String.init) ?? ""
        interval = c.interval.map(String.init) ?? ""
        dailyGoal = c.dailyGoal.map(String.init) ?? ""
        note = c.note
    }

    private func save() {
        do {
            let g = hasGoal ? try NumberParse.optionalPositive(goal, error: .goalOutOfRange) : nil
            if hasGoal && g == nil { throw EngineError.goalOutOfRange }
            let i = try NumberParse.optionalPositive(interval, error: .intervalOutOfRange)
            let d = try NumberParse.optionalPositive(dailyGoal, error: .dailyGoalOutOfRange)
            if let id = counterID {
                try store.updateCounter(id: id, title: title, goal: g, interval: i, dailyGoal: d, note: note)
            } else {
                let start = try NumberParse.nonNegative(initial, error: .valueOutOfRange)
                try store.createCounter(title: title, initial: start, goal: g, interval: i, dailyGoal: d, note: note)
                store.tab = .home
            }
            dismiss()
        } catch {
            errorText = store.message(for: error)
        }
    }
}

// MARK: - Program editor

private struct StepRow: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var target: String
}

struct ProgramEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: UUID?

    @State private var title = ""
    @State private var steps: [StepRow] = []
    @State private var note = ""
    @State private var errorText: String?
    @State private var loaded = false

    private var isNew: Bool { programID == nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steps.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("editor.programPlaceholder"), text: $title)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text(store.t("editor.title"))
                } footer: {
                    Text(store.t("editor.programFooter"))
                }

                if isNew {
                    Section(store.t("editor.templates")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                template([33, 33, 34])
                                template([33, 33, 33])
                                template([100])
                                template([10, 10, 10])
                                template([7, 7, 7, 7, 7, 7, 7])
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    ForEach($steps) { $step in
                        HStack(spacing: 10) {
                            Text(store.num((steps.firstIndex(of: step) ?? 0) + 1))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            TextField(store.t("editor.stepPlaceholder"), text: $step.title)
                            TextField("33", text: $step.target)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: step.target) { _, value in
                                    let digits = value.filter(\.isNumber)
                                    if digits != value { step.target = digits }
                                }
                                .accessibilityLabel(store.t("editor.stepTarget"))
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    if steps.count < Limits.steps {
                        Button {
                            steps.append(StepRow(title: store.f("starter.step", store.num(steps.count + 1)), target: "33"))
                        } label: {
                            Label(store.t("editor.addStep"), systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    HStack {
                        Text(store.t("editor.steps"))
                        Spacer()
                        if !steps.isEmpty { EditButton().font(.caption) }
                    }
                } footer: {
                    Text(store.f("editor.stepsTotal", store.num(steps.compactMap { Int($0.target) }.reduce(0, +))))
                }

                Section(store.t("editor.note")) {
                    TextField(store.t("editor.notePlaceholder"), text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? store.t("action.newProgram") : store.t("editor.editProgram"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("common.save"), action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func template(_ targets: [Int]) -> some View {
        Button {
            steps = targets.enumerated().map { index, target in
                StepRow(title: store.f("starter.step", store.num(index + 1)), target: String(target))
            }
        } label: {
            Text(targets.map { store.num($0) }.joined(separator: " · "))
                .font(.subheadline.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.zSoft, in: Capsule())
                .foregroundStyle(Color.zPrimary)
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = programID, let p = store.data.program(id) {
            title = p.title
            note = p.note
            steps = p.steps.map { StepRow(title: $0.title, target: String($0.target)) }
        } else {
            steps = [33, 33, 34].enumerated().map { index, target in
                StepRow(title: store.f("starter.step", store.num(index + 1)), target: String(target))
            }
        }
    }

    private func save() {
        do {
            let drafts = try steps.map { row -> StepDraft in
                guard let target = Int(row.target), (1...Limits.maxValue).contains(target) else {
                    throw EngineError.stepTargetOutOfRange
                }
                return StepDraft(title: row.title, target: target)
            }
            if let id = programID {
                try store.updateProgram(id: id, title: title, steps: drafts, note: note)
            } else {
                try store.createProgram(title: title, steps: drafts, note: note)
                store.tab = .home
            }
            dismiss()
        } catch {
            errorText = store.message(for: error)
        }
    }
}

// MARK: - Correction

struct CorrectionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let counterID: UUID
    @State private var value = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: store.t("correct.newValue"), text: $value)
                } footer: {
                    Text(store.t("correct.footer"))
                }
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
            }
            .navigationTitle(store.t("action.correct"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("common.save")) {
                        do {
                            guard let number = Int(value) else { throw EngineError.valueOutOfRange }
                            try store.adjust(counterID: counterID, to: number)
                            dismiss()
                        } catch {
                            errorText = store.message(for: error)
                        }
                    }
                    .disabled(value.isEmpty)
                }
            }
            .onAppear {
                if value.isEmpty, let c = store.data.counter(counterID) { value = String(c.value) }
            }
        }
        .presentationDetents([.medium])
    }
}
