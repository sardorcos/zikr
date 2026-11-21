import AppIntents
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var shareURL: URL?
    @State private var importing = false
    @State private var pendingImport: ZikrData?
    @State private var reminderRef: ItemRef?

    var body: some View {
        NavigationStack {
            Form {
                general
                counting
                Section {
                    NavigationLink {
                        HandsFreeGuideView()
                    } label: {
                        Label(store.t("settings.handsFree"), systemImage: "hand.tap")
                    }
                } footer: {
                    Text(store.t("settings.handsFreeFooter"))
                }
                reminders
                dataSection
                about
            }
            .navigationTitle(store.t("tab.settings"))
            .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
            .sheet(item: $reminderRef) { ReminderSheet(ref: $0).storeAlert() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog(store.t("backup.restoreConfirm"), isPresented: Binding(
                get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
                Button(store.t("backup.restore"), role: .destructive) {
                    if let data = pendingImport {
                        do { try store.restore(data) } catch { store.show(error) }
                    }
                    pendingImport = nil
                }
                Button(store.t("common.cancel"), role: .cancel) { pendingImport = nil }
            } message: {
                if let data = pendingImport {
                    Text(store.f("backup.preview", store.num(data.counters.count), store.num(data.programs.count)))
                }
            }
        }
    }

    // MARK: Sections

    private var general: some View {
        Section(store.t("settings.general")) {
            Picker(selection: Binding(get: { store.data.settings.language }, set: { store.setLanguage($0) })) {
                Text(store.t("settings.languageSystem")).tag(AppLanguage?.none)
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(AppLanguage?.some(language))
                }
            } label: {
                Label(store.t("settings.language"), systemImage: "globe")
            }
            Picker(selection: Binding(get: { store.data.settings.appearance }, set: { store.setAppearance($0) })) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(store.t("appearance.\(appearance.rawValue)")).tag(appearance)
                }
            } label: {
                Label(store.t("settings.appearance"), systemImage: "circle.lefthalf.filled")
            }
            Toggle(isOn: Binding(get: { store.data.settings.haptics }, set: { store.setHaptics($0) })) {
                Label(store.t("settings.haptics"), systemImage: "iphone.radiowaves.left.and.right")
            }
        }
    }

    private var counting: some View {
        Section {
            Toggle(isOn: Binding(get: { store.data.settings.keepScreenOn }, set: { store.setKeepScreenOn($0) })) {
                Label(store.t("settings.keepScreenOn"), systemImage: "sun.max")
            }
            Toggle(isOn: Binding(get: { store.data.settings.nightShowDigits }, set: { store.setNightShowDigits($0) })) {
                Label(store.t("settings.nightDigits"), systemImage: "moon")
            }
            if store.data.settings.nightShowDigits {
                VStack(alignment: .leading) {
                    Text(store.t("settings.nightBrightness")).font(.subheadline)
                    Slider(value: Binding(get: { store.data.settings.nightDigitsOpacity },
                                          set: { store.setNightOpacity($0) }), in: 0.1...1) {
                        Text(store.t("settings.nightBrightness"))
                    } minimumValueLabel: {
                        Image(systemName: "sun.min")
                    } maximumValueLabel: {
                        Image(systemName: "sun.max")
                    }
                }
            }
        } header: {
            Text(store.t("settings.counting"))
        } footer: {
            Text(store.t("settings.keepScreenOnFooter"))
        }
    }

    private var reminders: some View {
        Section {
            if store.data.reminders.isEmpty {
                Text(store.t("settings.noReminders")).foregroundStyle(.secondary)
            }
            ForEach(store.data.reminders) { reminder in
                Button {
                    reminderRef = reminder.target
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.data.title(of: reminder.target) ?? "—").foregroundStyle(.primary)
                            Text(daysText(reminder)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(timeText(reminder)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(store.t("settings.reminders"))
        } footer: {
            Text(store.t("settings.remindersFooter"))
        }
    }

    private var dataSection: some View {
        Section {
            if !AppGroup.isSharedContainerAvailable {
                Label(store.t("settings.appGroupMissing"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Button {
                do { shareURL = try store.makeBackupFile() } catch { store.show(error) }
            } label: {
                Label(store.t("backup.export"), systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label(store.t("backup.import"), systemImage: "square.and.arrow.down")
            }
            NavigationLink {
                SnapshotsView()
            } label: {
                Label(store.t("backup.snapshots"), systemImage: "clock.arrow.circlepath")
            }
        } header: {
            Text(store.t("settings.data"))
        } footer: {
            Text(store.t("settings.dataFooter"))
        }
    }

    private var about: some View {
        Section {
            LabeledContent(store.t("settings.version"), value: RuntimeInfo.version)
            if let url = RuntimeInfo.privacyPolicyURL {
                Link(destination: url) { Label(store.t("settings.privacy"), systemImage: "hand.raised") }
            }
            if let url = RuntimeInfo.supportURL {
                Link(destination: url) { Label(store.t("settings.support"), systemImage: "questionmark.circle") }
            }
        } header: {
            Text(store.t("settings.about"))
        } footer: {
            Text(store.t("settings.aboutFooter"))
        }
    }

    // MARK: Helpers

    private func timeText(_ reminder: Reminder) -> String {
        let date = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().minute().locale(store.locale))
    }

    private func daysText(_ reminder: Reminder) -> String {
        if Set(reminder.weekdays) == Set(1...7) { return store.t("reminders.everyDay") }
        let symbols = L10n.weekdaySymbols(store.language)
        return L10n.orderedWeekdays(store.language)
            .filter { reminder.weekdays.contains($0) }
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let raw = try Data(contentsOf: url)
            pendingImport = try store.previewBackup(raw)
        } catch {
            store.show(error)
        }
    }
}

struct SnapshotsView: View {
    @Environment(AppStore.self) private var store
    @State private var pending: SnapshotInfo?

    var body: some View {
        List {
            let snapshots = store.snapshots()
            if snapshots.isEmpty {
                ContentUnavailableView(store.t("backup.noSnapshots"), systemImage: "clock")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(snapshots) { snapshot in
                        Button {
                            pending = snapshot
                        } label: {
                            Label(L10n.shortDate(snapshot.day, store.language), systemImage: "doc")
                        }
                    }
                } footer: {
                    Text(store.t("backup.snapshotsFooter"))
                }
            }
        }
        .navigationTitle(store.t("backup.snapshots"))
        .confirmationDialog(store.t("backup.restoreConfirm"), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(store.t("backup.restore"), role: .destructive) {
                if let snapshot = pending {
                    do { try store.restoreSnapshot(snapshot) } catch { store.show(error) }
                }
                pending = nil
            }
            Button(store.t("common.cancel"), role: .cancel) { pending = nil }
        }
    }
}

struct HandsFreeGuideView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                Text(store.t("handsFree.intro")).foregroundStyle(.secondary)
                SiriTipView(intent: IncrementIntent())
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            }
            guide(icon: "button.horizontal.top.press", title: "handsFree.action.title", steps: "handsFree.action.steps")
            guide(icon: "hand.tap", title: "handsFree.backTap.title", steps: "handsFree.backTap.steps")
            guide(icon: "lock.iphone", title: "handsFree.live.title", steps: "handsFree.live.steps")
            guide(icon: "square.grid.2x2", title: "handsFree.widget.title", steps: "handsFree.widget.steps")
            guide(icon: "switch.2", title: "handsFree.control.title", steps: "handsFree.control.steps")
            guide(icon: "moon.fill", title: "handsFree.night.title", steps: "handsFree.night.steps")
        }
        .navigationTitle(store.t("settings.handsFree"))
    }

    private func guide(icon: String, title: String, steps: String) -> some View {
        Section {
            ForEach(Array(store.t(steps).components(separatedBy: "\n").enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(store.num(index + 1))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.zPrimary)
                        .frame(width: 20)
                    Text(step)
                }
            }
        } header: {
            Label(store.t(title), systemImage: icon)
        }
    }
}
