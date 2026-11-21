# ZIKR 1.0 (iOS)

Офлайн-счётчик для ежедневной практики: свободные счётчики, программы из нескольких шагов, счёт без взгляда на экран (кнопка действия, экран блокировки, виджет, Пункт управления, ночной режим), честная статистика. Без рекламы, аналитики и учётных записей. В приложении нет религиозных текстов: названия и заметки пишет пользователь.

## Структура

| Папка | Что внутри |
|---|---|
| `Shared/` | Общий код приложения и виджетов: модели (схема v4), движок, хранилище, миграции, интенты, локализация |
| `ZIKR/` | Приложение: `App/` (состояние, точка входа), `Services/` (синхронизация, напоминания, Live Activity, вибрация), `Views/` |
| `ZIKRWidgets/` | Виджет, Live Activity, элемент Пункта управления |
| `ZIKRTests/` | Юнит-тесты (Swift Testing) |
| `Config/` | Info.plist и entitlements |
| `tools/` | Генераторы: проект Xcode, локализация, иконки |
| `scripts/` | Настройка подписи и загрузка в TestFlight |
| `docs/` | Политика конфиденциальности, тексты для App Store, аудит |

## Сборка

Нужен Mac с **Xcode 26** и Apple Developer Program.

1. Один раз впишите свою команду и идентификатор:
   ```bash
   ./scripts/configure.sh ABCDE12345 com.yourname.zikr https://yourname.github.io/zikr/privacy https://yourname.github.io/zikr/support
   ```
   Team ID: Xcode → Settings → Accounts. App Group `group.<bundle id>` создаётся автоматически при автоматической подписи.
2. Откройте `ZIKR.xcodeproj`, схема **ZIKR**, запустите на симуляторе или iPhone (⌘R). Тесты: ⌘U.

## TestFlight

1. В [App Store Connect](https://appstoreconnect.apple.com) создайте приложение с тем же Bundle ID.
2. Создайте API-ключ: Users and Access → Integrations → App Store Connect API, роль App Manager. Скачайте `.p8`.
3. Запустите:
   ```bash
   export ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ASC_KEY_PATH=~/AuthKey_XXXXXXXXXX.p8
   ./scripts/testflight.sh
   ```
   Скрипт проверит локализацию, прогонит тесты, соберёт Release-архив и загрузит его. Номер сборки ставится по дате.

Без своего Mac: отправьте репозиторий на GitHub, добавьте секреты `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` и запустите workflow **TestFlight** (`.github/workflows/testflight.yml`).

## Генераторы

```bash
python3 tools/gen_l10n.py --check   # после правки tools/strings.json (узбекская кириллица генерируется из латиницы)
python3 tools/gen_project.py        # только при изменении таргетов или настроек сборки
python3 tools/gen_icons.py          # тёмный и тонированный варианты иконки
```

Папки синхронизированы с Xcode: новые `.swift`-файлы подхватываются без правки проекта.

## Хранение данных

Один JSON-файл в общем контейнере App Group (`zikr-data.json`), схема v4: агрегаты по дням вместо записи на каждое нажатие, поэтому размер не растёт с числом нажатий. Все чтения и записи идут через `NSFileCoordinator`. Приложение применяет изменения мгновенно в памяти и повторяет их поверх текущего файла в фоне, поэтому изменения от виджета не теряются. Нечитаемый файл никогда не перезаписывается: он откладывается, и пользователь выбирает, что делать. Каждый день сохраняется автокопия (7 дней). Импортируются копии схем v3 и v4.
