import SwiftUI

struct ItemsView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: EditorSheet?
    @State private var pendingArchive: ItemRow?

    var body: some View {
        NavigationStack {
            List {
                let rows = store.rows()
                let counters = rows.filter { !$0.isProgram }
                let programs = rows.filter(\.isProgram)

                if rows.isEmpty {
                    ContentUnavailableView {
                        Label(store.t("home.emptyTitle"), systemImage: "circle.hexagongrid")
                    } description: {
                        Text(store.t("home.emptyBody"))
                    }
                    .listRowBackground(Color.clear)
                }

                if !counters.isEmpty {
                    Section {
                        ForEach(counters) { row($0) }
                    } header: {
                        Text(store.t("items.counters"))
                    } footer: {
                        Text(store.f("items.countersFooter", store.num(store.data.activeCounters.count), store.num(Limits.activeCounters)))
                    }
                }

                if !programs.isEmpty {
                    Section {
                        ForEach(programs) { row($0) }
                    } header: {
                        Text(store.t("items.programs"))
                    } footer: {
                        Text(store.t("items.programsFooter"))
                    }
                }

                Section {
                    NavigationLink {
                        ArchiveView()
                    } label: {
                        Label(store.f("items.archive", store.num(store.rows(archived: true).count)), systemImage: "archivebox")
                    }
                }
            }
            .navigationTitle(store.t("tab.items"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { sheet = .newCounter } label: { Label(store.t("action.newCounter"), systemImage: "circle.circle") }
                        Button { sheet = .newProgram } label: { Label(store.t("action.newProgram"), systemImage: "list.number") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(store.t("action.create"))
                }
            }
            .sheet(item: $sheet) { EditorSheetContent(sheet: $0) }
            .confirmationDialog(store.t("home.archiveConfirm"), isPresented: Binding(
                get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } }), titleVisibility: .visible) {
                Button(store.t("action.archive"), role: .destructive) {
                    if let row = pendingArchive { store.archive(row.ref) }
                    pendingArchive = nil
                }
                Button(store.t("common.cancel"), role: .cancel) { pendingArchive = nil }
            } message: {
                Text(store.t("home.archiveMessage"))
            }
        }
    }

    private func row(_ row: ItemRow) -> some View {
        Button {
            store.select(row.ref)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.icon(for: row.ref))
                    .foregroundStyle(Color.zPrimary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if row.pinned {
                    Image(systemName: "pin.fill").foregroundStyle(Color.zAccentText)
                        .accessibilityLabel(store.t("items.pinned"))
                }
                if row.ref == store.activeRef {
                    Image(systemName: "checkmark").foregroundStyle(Color.zPrimary)
                        .accessibilityLabel(store.t("items.current"))
                }
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingArchive = row } label: {
                Label(store.t("action.archive"), systemImage: "archivebox")
            }
            Button {
                sheet = row.isProgram ? .editProgram(row.ref.id) : .editCounter(row.ref.id)
            } label: {
                Label(store.t("action.edit"), systemImage: "pencil")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading) {
            Button { store.togglePin(row.ref) } label: {
                Label(row.pinned ? store.t("action.unpin") : store.t("action.pin"), systemImage: row.pinned ? "pin.slash" : "pin")
            }
            .tint(Color.zAccent)
        }
    }
}

struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDelete: ItemRow?

    var body: some View {
        List {
            let rows = store.rows(archived: true)
            if rows.isEmpty {
                ContentUnavailableView(store.t("archive.empty"), systemImage: "archivebox")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(rows) { row in
                        HStack {
                            Image(systemName: store.icon(for: row.ref)).foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(row.title)
                                Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = row } label: {
                                Label(store.t("action.delete"), systemImage: "trash")
                            }
                            Button { store.unarchive(row.ref) } label: {
                                Label(store.t("action.restore"), systemImage: "arrow.uturn.backward")
                            }
                            .tint(Color.zPrimary)
                        }
                        .contextMenu {
                            Button { store.unarchive(row.ref) } label: {
                                Label(store.t("action.restore"), systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) { pendingDelete = row } label: {
                                Label(store.t("action.delete"), systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text(store.t("archive.footer"))
                }
            }
        }
        .navigationTitle(store.t("archive.title"))
        .confirmationDialog(store.t("archive.deleteConfirm"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(store.t("action.delete"), role: .destructive) {
                if let row = pendingDelete { store.delete(row.ref) }
                pendingDelete = nil
            }
            Button(store.t("common.cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(store.t("archive.deleteMessage"))
        }
    }
}
