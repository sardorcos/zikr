#if DEBUG
import Foundation

/// Debug-only demo content for App Store screenshots taken in the simulator.
/// Activated with the launch argument `-ZIKRScreenshots`; optional `-ZIKRTab home|items|stats|settings`
/// and `-ZIKRNight`. Nothing is written to disk while it is active. Not compiled into Release builds.
enum ScreenshotDemo {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-ZIKRScreenshots") }

    static var tab: AppTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ZIKRTab"), i + 1 < args.count else { return .home }
        switch args[i + 1] {
        case "items": return .items
        case "stats": return .stats
        case "settings": return .settings
        default: return .home
        }
    }

    static var night: Bool { ProcessInfo.processInfo.arguments.contains("-ZIKRNight") }

    static func data(language: AppLanguage) -> ZikrData {
        let ru = language == .ru
        let uz = language == .uz || language == .uzCyrl
        func t(_ ruText: String, _ uzText: String, _ enText: String) -> String { ru ? ruText : (uz ? uzText : enText) }

        let calendar = DayKey.calendar()
        let today = Date()
        func dayKey(_ offset: Int) -> String {
            DayKey.key(calendar.date(byAdding: .day, value: -offset, to: today) ?? today, calendar: calendar)
        }
        // Deterministic, natural-looking history: most days active, a few gaps, weekends a bit higher.
        func history(days: Int, base: Int, seed: Int) -> [String: Int] {
            var out: [String: Int] = [:]
            var x = UInt64(seed)
            for offset in 0..<days {
                x = x &* 6364136223846793005 &+ 1442695040888963407
                let r = Int((x >> 33) % 100)
                if r < 9 && offset > 0 { continue }
                let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -offset, to: today) ?? today)
                let bonus = (weekday == 1 || weekday == 7) ? base / 3 : 0
                out[dayKey(offset)] = base + bonus + (r % 40)
            }
            return out
        }

        var data = ZikrData()
        data.onboardingDone = true

        var morning = Counter(title: t("Утро", "Tong", "Morning"))
        morning.daily = history(days: 190, base: 90, seed: 7)
        morning.value = morning.daily.values.reduce(0, +)
        morning.dailyGoal = 100
        morning.goal = 25_000
        morning.pinned = true

        var evening = Counter(title: t("Вечер", "Kechqurun", "Evening"))
        evening.daily = history(days: 120, base: 60, seed: 11)
        evening.value = evening.daily.values.reduce(0, +)
        evening.interval = 33

        var walk = Counter(title: t("Прогулка", "Sayr", "Walk"))
        walk.daily = history(days: 40, base: 20, seed: 23)
        walk.value = walk.daily.values.reduce(0, +)

        var program = Program(
            title: t("Моя программа", "Mening dasturim", "My program"),
            steps: [
                ProgramStep(title: t("Шаг 1", "1-qadam", "Step 1"), target: 33),
                ProgramStep(title: t("Шаг 2", "2-qadam", "Step 2"), target: 33),
                ProgramStep(title: t("Шаг 3", "3-qadam", "Step 3"), target: 34),
            ])
        program.daily = history(days: 150, base: 100, seed: 3)
        for (key, value) in program.daily { program.completions[key] = max(1, value / 100) }
        program.pinned = true
        var session = ProgramSession()
        session.stepIndex = 1
        session.count = 21
        session.dayRuns = [DayRun(day: dayKey(0), count: 54)]
        program.session = session

        data.counters = [morning, evening, walk]
        data.programs = [program]
        data.active = .program(program.id)
        return data
    }
}
#endif
