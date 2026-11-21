import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let issue = store.loadIssue {
                RecoveryView(issue: issue)
            } else if !store.data.onboardingDone {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        .storeAlert()
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab(store.t("tab.count"), systemImage: "circle.circle", value: AppTab.home) {
                HomeView()
            }
            Tab(store.t("tab.items"), systemImage: "list.bullet", value: AppTab.items) {
                ItemsView()
            }
            Tab(store.t("tab.stats"), systemImage: "chart.bar", value: AppTab.stats) {
                StatsView()
            }
            Tab(store.t("tab.settings"), systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sheet(item: $store.completion) { info in
            CompletionSheet(info: info)
                .presentationDetents([.medium])
        }
        .alert(store.t("recovered.title"), isPresented: Binding(
            get: { store.recoveredElements > 0 },
            set: { if !$0 { store.recoveredElements = 0 } })) {
            Button(store.t("common.ok")) { store.recoveredElements = 0 }
        } message: {
            Text(store.t("recovered.message"))
        }
    }
}

struct CompletionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let info: CompletionInfo

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.zAccent)
                .symbolEffect(.bounce, value: info.id)
                .accessibilityHidden(true)
            Text(store.t("completion.title"))
                .font(.title2.weight(.semibold))
            Text(info.title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let program = store.data.program(info.programID) {
                Text(store.f("completion.todayCount", store.num(program.completions[DayKey.key(Date())] ?? 0)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text(store.t("completion.again")).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    dismiss()
                    store.tab = .stats
                } label: {
                    Text(store.t("completion.stats")).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }
}
