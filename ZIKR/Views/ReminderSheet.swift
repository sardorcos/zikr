import SwiftUI

struct ReminderSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ref: ItemRef

    @State private var enabled = true
    @State private var time = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var days: Set<Int> = Set(1...7)
    @State private var saving = false
    @State private var loaded = false
    @State private var reminderID = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(store.t("reminders.enable"), isOn: $enabled.animation())
                } footer: {
                    Text(store.f("reminders.footer", store.data.title(of: ref) ?? ""))
                }

                if enabled {
                    Section {
                        DatePicker(store.t("reminders.time"), selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Section(store.t("reminders.days")) {
                        let symbols = L10n.weekdaySymbols(store.language)
                        HStack(spacing: 6) {
                            ForEach(L10n.orderedWeekdays(store.language), id: \.self) { day in
                                let on = days.contains(day)
                                Button {
                                    if on { days.remove(day) } else { days.insert(day) }
                                } label: {
                                    Text(symbols[day - 1])
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(on ? Color.zOnPrimary : Color.zPrimary)
                                        .background(on ? Color.zPrimary : Color.zSoft, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        HStack {
                            Button(store.t("reminders.everyDay")) { days = Set(1...7) }
                            Spacer()
                            Button(store.t("reminders.weekdays")) { days = [2, 3, 4, 5, 6] }
                        }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Text(store.f("reminders.limit", store.num(Limits.reminders)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("action.reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("common.save"), action: save)
                        .disabled(saving || (enabled && days.isEmpty))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing = store.reminder(for: ref) else { return }
        reminderID = existing.id
        enabled = existing.enabled
        days = Set(existing.weekdays)
        time = Calendar.current.date(bySettingHour: existing.hour, minute: existing.minute, second: 0, of: Date()) ?? time
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var reminder = Reminder(target: ref)
        reminder.id = reminderID
        reminder.hour = parts.hour ?? 21
        reminder.minute = parts.minute ?? 0
        reminder.weekdays = days.sorted()
        reminder.enabled = enabled
        saving = true
        Task {
            let saved = await store.saveReminder(reminder)
            saving = false
            if saved { dismiss() }
        }
    }
}
