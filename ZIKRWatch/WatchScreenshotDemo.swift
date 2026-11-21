#if DEBUG
import Foundation

/// Debug-only demo snapshot for App Store screenshots in the watch simulator (`-ZIKRScreenshots`).
enum WatchScreenshotDemo {
    static func snapshotIfRequested() -> WatchSnapshot? {
        guard ProcessInfo.processInfo.arguments.contains("-ZIKRScreenshots") else { return nil }
        let ru = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ru")
        let programID = "program:5B3C1F2E-6A0D-4C4B-9E43-1C2A7F0D9A11"
        let steps = (1...3).map { WatchStep(title: ru ? "Шаг \($0)" : "Step \($0)", target: $0 == 3 ? 34 : 33) }
        let items = [
            WatchItem(id: programID, kind: .program, title: ru ? "Моя программа" : "My program", value: 21, goal: nil, interval: nil,
                      steps: steps, stepIndex: 1, today: 152, pinned: true),
            WatchItem(id: "counter:0E5D6A39-2B7F-4F0E-8C55-0B1D8D7F3A21", kind: .counter, title: ru ? "Утро" : "Morning", value: 19_871,
                      goal: 25_000, interval: nil, steps: [], stepIndex: 0, today: 96, pinned: true),
            WatchItem(id: "counter:7A4B2C11-9D3E-4E2F-A1B0-5C6D7E8F9012", kind: .counter, title: ru ? "Вечер" : "Evening", value: 9_123,
                      goal: nil, interval: 33, steps: [], stepIndex: 0, today: 66, pinned: false),
        ]
        return WatchSnapshot(items: items, activeID: programID, language: ru ? "ru" : "en", haptics: true, applied: [], generatedAt: Date())
    }
}
#endif
