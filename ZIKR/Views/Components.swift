import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Row model used by lists and menus.
struct ItemRow: Identifiable, Hashable {
    var ref: ItemRef
    var title: String
    var subtitle: String
    var pinned: Bool
    var archived: Bool
    var isProgram: Bool { ref.kind == .program }
    var id: ItemRef { ref }
}

extension AppStore {
    func rows(archived: Bool = false) -> [ItemRow] {
        let counters = data.counters.filter { $0.archived == archived }.map { c in
            ItemRow(ref: .counter(c.id), title: c.title,
                    subtitle: c.goal.map { "\(num(c.value)) / \(num($0))" } ?? num(c.value),
                    pinned: c.pinned, archived: c.archived)
        }
        let programs = data.programs.filter { $0.archived == archived }.map { p in
            ItemRow(ref: .program(p.id), title: p.title,
                    subtitle: p.steps.map { num($0.target) }.joined(separator: " · "),
                    pinned: p.pinned, archived: p.archived)
        }
        let all = counters + programs
        // Stable order: pinned first, then the order items were created in.
        return all.enumerated().sorted { a, b in
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            return a.offset < b.offset
        }.map(\.element)
    }

    func icon(for ref: ItemRef) -> String {
        ref.kind == .program ? "list.number" : "circle.circle"
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.zSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.zAccentText)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.zPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Number field that keeps only digits and reports parsing errors via `nil`.
struct NumberField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        LabeledContent(title) {
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
                .onChange(of: text) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                }
                .accessibilityLabel(title)
        }
    }
}

enum NumberParse {
    /// Empty → nil. Non-empty must be 1…max.
    static func optionalPositive(_ text: String, error: EngineError) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (1...Limits.maxValue).contains(value) else { throw error }
        return value
    }

    static func nonNegative(_ text: String, error: EngineError) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = Int(trimmed), (0...Limits.maxValue).contains(value) else { throw error }
        return value
    }
}

/// `ItemRef.id` (the item's UUID) already satisfies Identifiable.
extension ItemRef: Identifiable {}

/// Shows `store.alert` from whatever is topmost. Sheets and full-screen covers need their own
/// copy because an alert attached below a presented sheet cannot appear.
struct StoreAlertModifier: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(item: $store.alert) { info in
            if info.action == .openNotificationSettings {
                return Alert(title: Text(info.title), message: Text(info.message),
                             primaryButton: .default(Text(store.t("common.openSettings"))) {
                                 if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                     UIApplication.shared.open(url)
                                 }
                             },
                             secondaryButton: .cancel(Text(store.t("common.cancel"))))
            }
            return Alert(title: Text(info.title), message: Text(info.message),
                         dismissButton: .default(Text(store.t("common.ok"))))
        }
    }
}

extension View {
    func storeAlert() -> some View { modifier(StoreAlertModifier()) }
}
