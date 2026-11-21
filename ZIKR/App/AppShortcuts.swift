import AppIntents

/// Exposes counting to Siri, Spotlight, the Shortcuts app and the iPhone Action button.
struct ZikrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IncrementIntent(),
            phrases: [
                "Add one in \(.applicationName)",
                "Count in \(.applicationName)",
                "\(.applicationName) plus one"
            ],
            shortTitle: LocalizedStringResource("shortcut.increment", defaultValue: "Add one"),
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: UndoIntent(),
            phrases: [
                "Undo in \(.applicationName)",
                "Undo last tap in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("shortcut.undo", defaultValue: "Undo"),
            systemImageName: "arrow.uturn.backward.circle"
        )
        AppShortcut(
            intent: CurrentCountIntent(),
            phrases: [
                "What is my count in \(.applicationName)",
                "Current count in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("shortcut.current", defaultValue: "Current count"),
            systemImageName: "number.circle"
        )
    }
}
