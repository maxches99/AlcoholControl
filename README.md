# AlcoholControl

AlcoholControl - iOS-приложение в стиле harm-reduction для контроля вечерних сессий: оценка BAC, вода/питание, утренний чек-ин, weekly-аналитика, виджет и Apple Watch-компаньон.

## Что умеет приложение

- Ведение активной сессии: напитки, вода, еда, завершение сессии.
- Оценка пикового BAC и примерного времени до `0.00`.
- Утренний чек-ин (самочувствие, симптомы, сон, вода).
- Уведомления: вода, bedtime-water, утренний чек-ин, smart risk nudge.
- Интеграция с Apple Health: сон, шаги, resting HR, HRV.
- Weekly safety-аналитика (heavy mornings, memory-risk, hydration, recovery/process scores).
- Экспорт данных в CSV и JSON backup.
- Подписка Premium через StoreKit (`monthly` / `yearly`).
- Виджет и Live Activity.
- Apple Watch быстрые действия через общий App Group.
- Локализация: `ru`, `en`, `es`, `zh-Hans` (+ системный язык).

## Стек

- SwiftUI
- SwiftData
- StoreKit 2
- UserNotifications
- HealthKit
- WidgetKit / ActivityKit

## Требования

- Xcode 26.2+
- iOS 26.0+ (основное приложение и виджет)
- watchOS 10.6+ (watch target)
- Apple Developer аккаунт для теста покупок/entitlements на устройстве

## Структура проекта

- `AlcoholControl/` - основное iOS-приложение.
- `AlcoholControlWidget/` - виджет + Live Activity UI.
- `AlcoholControlWatch/` - watchOS-компаньон.
- `AlcoholControlTests/` - unit tests.
- `AlcoholControlUITests/` - UI tests.
- `Config/AlcoholControlWidget-Info.plist` - Info.plist для widget target.

## Быстрый старт

1. Откройте `AlcoholControl.xcodeproj` в Xcode.
2. Выберите схему `AlcoholControl` и симулятор iPhone.
3. Запустите `Run`.

## Сборка и тесты из CLI

```bash
# Список таргетов/схем
xcodebuild -list -project AlcoholControl.xcodeproj

# Сборка iOS приложения
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -configuration Debug \
  -sdk iphonesimulator \
  build

# Запуск unit tests
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

## Важные технические детали

- Хранилище данных: SwiftData (`UserProfile`, `Session`, `DrinkEntry`, `WaterEntry`, `MealEntry`, `MorningCheckIn`, `HealthDailySnapshot`, `RiskModelRun`).
- Общий контейнер для app/widget/watch: `group.maxches.AlcoholControl`.
- HealthKit entitlement включён в основном приложении.
- Виджет читает снэпшот состояния из `UserDefaults(suiteName: appGroupID)`.
- Быстрые действия watch/widget синхронизируются через `WidgetSnapshotStore`.

## Конфиденциальность и безопасность

- Приложение ориентировано на harm-reduction и самоконтроль.
- Оценки BAC и recovery носят ориентировочный характер и не являются медицинской рекомендацией.
- Для полноты функций нужны разрешения на уведомления и Apple Health.

## Статус тестов

В `AlcoholControlTests` есть базовый шаблон теста, покрытие пока минимальное. Перед релизом рекомендуется расширить тесты для `BACCalculator`, `SessionInsightService`, экспорта и sync-логики widget/watch.

