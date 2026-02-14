# AlcoholControl

AlcoholControl is a harm-reduction iOS app for tracking evening sessions: BAC estimation, hydration/food, morning check-in, weekly safety analytics (with a shareable weekly summary), plus a widget and Apple Watch companion.

## What the app does

- Active session tracking: drinks, water, food, session end.
- Peak BAC estimate and approximate time to `0.00`.
- Morning check-in (well-being, symptoms, sleep, water).
- Notifications: water, bedtime-water, morning check-in, smart risk nudge.
- Apple Health (HealthKit) integration: sleep, steps, resting HR, HRV.
- Weekly safety analytics (heavy mornings, memory-risk, hydration, recovery/process scores).
- Data export to CSV and JSON backup.
- Premium subscription via StoreKit (`monthly` / `yearly`).
- Widget and Live Activity.
- Apple Watch quick actions via shared App Group.
- CoreML shadow forecast (separate from the main risk estimate) with quality tracking.
- Localization: `ru`, `en`, `es`, `zh-Hans` (+ system language).

## Tech stack

- SwiftUI
- SwiftData
- StoreKit 2
- UserNotifications
- HealthKit
- WidgetKit / ActivityKit

## Requirements

- Xcode 26.2+
- iOS 26.0+ (main app and widget)
- watchOS 10.6+ (watch target)
- Apple Developer account to test purchases/entitlements on device

## Setup

1. Open `AlcoholControl.xcodeproj` in Xcode.
2. Select the `AlcoholControl` scheme and an iPhone simulator.
3. Run.
4. For device testing, ensure App Group and Health permissions are enabled for your signing team.

## Project structure

- `AlcoholControl/` - main iOS app.
- `AlcoholControlWidget/` - widget + Live Activity UI.
- `AlcoholControlWatch/` - watchOS companion.
- `AlcoholControlTests/` - unit tests.
- `AlcoholControlUITests/` - UI tests.
- `Config/AlcoholControlWidget-Info.plist` - Info.plist for the widget target.

## Build and test from CLI

```bash
# List targets/schemes
xcodebuild -list -project AlcoholControl.xcodeproj

# Build the iOS app
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -configuration Debug \
  -sdk iphonesimulator \
  build

# Run unit tests
xcodebuild \
  -project AlcoholControl.xcodeproj \
  -scheme AlcoholControl \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test

# Regenerate CoreML shadow models
./Scripts/generate_shadow_models.sh
```

## Key technical details

- Data store: SwiftData (`UserProfile`, `Session`, `DrinkEntry`, `WaterEntry`, `MealEntry`, `MorningCheckIn`, `HealthDailySnapshot`, `RiskModelRun`).
- Shared container for app/widget/watch: `group.maxches.AlcoholControl`.
- HealthKit entitlement is enabled only in the main app target.
- The widget reads state snapshots from `UserDefaults(suiteName: appGroupID)`.
- Watch/widget quick actions are synced via `WidgetSnapshotStore`.

## Privacy and safety

- The app focuses on harm-reduction and self-tracking.
- BAC and recovery estimates are approximate and not medical advice.
- Notifications and Apple Health permissions are required for full functionality.

## Troubleshooting

- Build fails on HealthKit: confirm HealthKit entitlement is enabled only for the main app target and your signing team has the capability.
- Widget/watch data not syncing: verify all targets use the same App Group ID `group.maxches.AlcoholControl` and the widget reads from `UserDefaults(suiteName: appGroupID)`.
- StoreKit products not loading on device: ensure you are signed into App Store, and the product IDs match `com.alcoholcontrol.premium.monthly` / `com.alcoholcontrol.premium.yearly`.
- Notifications not firing: confirm notification authorization was granted and the simulator/device is not in Focus/Do Not Disturb.

## Contributing

- Keep changes small and localized unless a refactor is explicitly requested.
- Keep business logic in `Services` and UI in `Views` without duplication.
- Route all user-facing strings through `L10n.tr(...)` / `L10n.format(...)`.
- If you change CoreML shadow features/weights, regenerate `AlcoholControl/ML/*.mlmodel`.
- Preserve the harm-reduction tone and avoid medical or legal-sounding claims.

## Test status

`AlcoholControlTests` currently includes a basic test template; coverage is minimal. Before release, expand tests for `BACCalculator`, `SessionInsightService`, export, and widget/watch sync logic.
