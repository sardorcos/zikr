import SwiftUI

/// Shown when the data file could not be read. Nothing is written until the user decides.
struct RecoveryView: View {
    @Environment(AppStore.self) private var store
    let issue: LoadIssue
    @State private var shareURL: URL?
    @State private var confirmFresh = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.zAccent)
                            .accessibilityHidden(true)
                        Text(title).font(.title3.weight(.semibold))
                        Text(message).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if let file = problemFile {
                    Section {
                        Button {
                            shareURL = file
                        } label: {
                            Label(store.t("recovery.shareFile"), systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if case .corrupt = issue {
                    let snapshots = store.snapshots()
                    if !snapshots.isEmpty {
                        Section(store.t("recovery.snapshots")) {
                            ForEach(snapshots) { snapshot in
                                Button {
                                    store.recoverFromSnapshot(snapshot)
                                } label: {
                                    Label(L10n.shortDate(snapshot.day, store.language), systemImage: "clock.arrow.circlepath")
                                }
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            confirmFresh = true
                        } label: {
                            Label(store.t("recovery.startFresh"), systemImage: "sparkles")
                        }
                    } footer: {
                        Text(store.t("recovery.startFreshFooter"))
                    }
                }
            }
            .navigationTitle("ZIKR")
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .confirmationDialog(store.t("recovery.startFresh"), isPresented: $confirmFresh, titleVisibility: .visible) {
                Button(store.t("recovery.startFresh"), role: .destructive) { store.startFresh() }
                Button(store.t("common.cancel"), role: .cancel) {}
            }
        }
    }

    private var title: String {
        switch issue {
        case .corrupt: return store.t("recovery.corruptTitle")
        case .newerVersion: return store.t("recovery.newerTitle")
        }
    }

    private var message: String {
        switch issue {
        case .corrupt: return store.t("recovery.corruptMessage")
        case .newerVersion: return store.t("recovery.newerMessage")
        }
    }

    private var problemFile: URL? {
        switch issue {
        case .corrupt(let url): return url ?? store.file.quarantinedFiles().first
        case .newerVersion: return store.file.url
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
