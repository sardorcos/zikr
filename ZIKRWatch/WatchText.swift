import Foundation

/// The handful of strings the watch shows, in the app's languages (the phone tells which one).
enum WatchText {
    private static let table: [String: [String: String]] = [
        "empty.title": ["ru": "Нет счётчиков", "uz": "Hisoblagich yo‘q", "uz-Cyrl": "Ҳисоблагич йўқ", "en": "No counters"],
        "empty.body": ["ru": "Откройте ZIKR на iPhone — счётчики появятся здесь.", "uz": "iPhone’da ZIKR’ni oching — hisoblagichlar shu yerda paydo bo‘ladi.",
                       "uz-Cyrl": "iPhone’да ZIKR’ни очинг — ҳисоблагичлар шу ерда пайдо бўлади.", "en": "Open ZIKR on your iPhone — your counters will appear here."],
        "of": ["ru": "из %@", "uz": "%@ dan", "uz-Cyrl": "%@ дан", "en": "of %@"],
        "step": ["ru": "Шаг %@", "uz": "%@-qadam", "uz-Cyrl": "%@-қадам", "en": "Step %@"],
        "today": ["ru": "Сегодня: %@", "uz": "Bugun: %@", "uz-Cyrl": "Бугун: %@", "en": "Today: %@"],
        "undo": ["ru": "Отменить", "uz": "Bekor qilish", "uz-Cyrl": "Бекор қилиш", "en": "Undo"],
        "list": ["ru": "Счётчики", "uz": "Hisoblagichlar", "uz-Cyrl": "Ҳисоблагичлар", "en": "Counters"],
        "programs": ["ru": "Программы", "uz": "Dasturlar", "uz-Cyrl": "Дастурлар", "en": "Programs"],
        "tap.hint": ["ru": "Коснитесь экрана, чтобы добавить 1", "uz": "1 qo‘shish uchun ekranga teging", "uz-Cyrl": "1 қўшиш учун экранга тегинг", "en": "Tap the screen to add 1"],
        "a11y.add": ["ru": "Плюс один", "uz": "Bitta qo‘shish", "uz-Cyrl": "Битта қўшиш", "en": "Add one"],
        "unsynced": ["ru": "Ждёт iPhone: %@", "uz": "iPhone kutilmoqda: %@", "uz-Cyrl": "iPhone кутилмоқда: %@", "en": "Waiting for iPhone: %@"],
        "milestone.interval": ["ru": "Круг", "uz": "Davra", "uz-Cyrl": "Давра", "en": "Round"],
        "milestone.goal": ["ru": "Цель достигнута", "uz": "Maqsadga erishildi", "uz-Cyrl": "Мақсадга эришилди", "en": "Goal reached"],
        "milestone.step": ["ru": "Следующий шаг", "uz": "Keyingi qadam", "uz-Cyrl": "Кейинги қадам", "en": "Next step"],
        "milestone.done": ["ru": "Программа завершена", "uz": "Dastur yakunlandi", "uz-Cyrl": "Дастур якунланди", "en": "Program completed"],
    ]

    static func t(_ key: String, _ lang: String) -> String {
        table[key]?[lang] ?? table[key]?["en"] ?? key
    }

    static func f(_ key: String, _ lang: String, _ arg: String) -> String {
        t(key, lang).replacingOccurrences(of: "%@", with: arg)
    }

    static func number(_ value: Int, _ lang: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: lang == "en" ? "en_US" : (lang == "ru" ? "ru_RU" : "uz_Latn_UZ"))
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
