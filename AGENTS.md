# AGENTS.md

Этот файл описывает рабочие правила для агентных изменений в проекте `AlcoholControl`.

## 1. Цель проекта

- `AlcoholControl` - iOS/watchOS приложение в подходе harm-reduction.
- Главный UX: быстро зафиксировать текущую сессию, гидратацию, риски утра и шаги восстановления.
- Не добавлять формулировки, которые выглядят как медицинский диагноз или юридический совет.

## 2. Где что находится

- `AlcoholControl/` - основная логика приложения (SwiftUI + SwiftData).
- `AlcoholControl/Services/` - бизнес-логика (`SessionService`, `BACCalculator`, `SessionInsightService`, `HealthKitService`, `NotificationService`, `PurchaseService`).
- `AlcoholControl/Models/` - SwiftData модели домена.
- `AlcoholControl/Views/` - экраны продукта.
- `AlcoholControlWidget/` - WidgetKit + Live Activity.
- `AlcoholControlWatch/` - watchOS UI и быстрые действия.
- `AlcoholControlTests/`, `AlcoholControlUITests/` - тесты.

## 3. Обязательные продуктовые инварианты

- Любые изменения расчётов BAC должны учитывать `UserProfile` (вес, unit system, sex).
- Изменения в `SessionService` не должны ломать recompute (`cachedPeakBAC`, `cachedEstimatedSoberAt`).
- Всё, что касается widget/watch quick actions, должно сохранять совместимость ключей в `WidgetSnapshotStore`.
- Все user-facing строки должны проходить через `L10n.tr(...)` / `L10n.format(...)`.
- Уважать privacy-настройку "Скрывать BAC в шаринге".
- Тон UX: поддерживающий harm-reduction, без нормализации рискованного поведения.

## 4. Entitlements и интеграции

- App Group: `group.maxches.AlcoholControl` (app/widget/watch).
- HealthKit только в основном target.
- Покупки: `com.alcoholcontrol.premium.monthly`, `com.alcoholcontrol.premium.yearly`.
- Перед изменениями widget/watch проверять, что данные читаются через один и тот же App Group suite.

## 5. Сборка и проверки

```bash
# Проверить схемы/таргеты
xcodebuild -list -project AlcoholControl.xcodeproj

# Базовая сборка iOS
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -configuration Debug \
  -sdk iphonesimulator \
  build

# Unit tests
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Если меняются `AlcoholControlWidget/` или `AlcoholControlWatch/`, дополнительно собрать соответствующие схемы.

## 6. Правила для изменений UI и логики

- Предпочитать небольшие, локальные правки вместо широкого рефакторинга без запроса.
- Для новых настроек использовать `@AppStorage` только при явной продуктовой необходимости.
- Для новых persisted-сущностей в SwiftData обновлять `Schema` в `AlcoholControlApp`.
- Не дублировать бизнес-логику между `Views` и `Services`; расчёты держать в сервисах.

## 7. Тестирование при изменениях

- Критичные зоны для регрессий: расчёты BAC/recovery.
- Критичные зоны для регрессий: утренние риски и weekly summary.
- Критичные зоны для регрессий: notification scheduling/cancel.
- Критичные зоны для регрессий: обмен данными app <-> widget/watch через App Group.

Минимум для PR с логическими изменениями:
- сборка целевой схемы.
- один тест на изменённую ветку поведения (если затронуты расчёты/сервисы).

## 8. Что не делать без отдельного запроса

- Не менять bundle identifiers / entitlements / App Group ID.
- Не переименовывать product IDs подписки.
- Не удалять локализации и ключи строк.
- Не менять форматы экспорта CSV/JSON, если это может сломать обратную совместимость.
