# AGENTS.md

This file defines the working rules for agent-driven changes in the `AlcoholControl` project.

## 1. Project goal

- `AlcoholControl` is an iOS/watchOS app built with a harm-reduction approach.
- Core UX: quickly log the current session, hydration, morning check-in and risks, and recovery steps.
- Do not add wording that reads like a medical diagnosis or legal advice.

## 2. Where things live

- `AlcoholControl/` - main app logic (SwiftUI + SwiftData).
- `AlcoholControl/Services/` - business logic (`SessionService`, `BACCalculator`, `SessionInsightService`, `HealthKitService`, `NotificationService`, `PurchaseService`).
- `AlcoholControl/Models/` - SwiftData domain models.
- `AlcoholControl/Views/` - product screens.
- `AlcoholControlWidget/` - WidgetKit + Live Activity.
- `AlcoholControlWatch/` - watchOS UI and quick actions.
- `AlcoholControlTests/`, `AlcoholControlUITests/` - tests.

## 3. Required product invariants

- Any BAC calculation change must account for `UserProfile` (weight, unit system, sex).
- Changes in `SessionService` must not break recompute (`cachedPeakBAC`, `cachedEstimatedSoberAt`).
- Widget/watch quick actions must preserve key compatibility in `WidgetSnapshotStore`.
- All user-facing strings must go through `L10n.tr(...)` / `L10n.format(...)`.
- Respect the privacy setting "Hide BAC in sharing".
- UX tone: supportive harm-reduction, no normalization of risky behavior.

## 4. Entitlements and integrations

- App Group: `group.maxches.AlcoholControl` (app/widget/watch).
- HealthKit only in the main target.
- Purchases: `com.alcoholcontrol.premium.monthly`, `com.alcoholcontrol.premium.yearly`.
- Before widget/watch changes, verify data is read through the same App Group suite.

## 5. Builds and checks

```bash
# List schemes/targets
xcodebuild -list -project AlcoholControl.xcodeproj

# Base iOS build
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

If `AlcoholControlWidget/` or `AlcoholControlWatch/` changes, also build the corresponding schemes.

## 6. Rules for UI and logic changes

- Prefer small, local edits over broad refactors without a request.
- Use `@AppStorage` for new settings only when there is a clear product need.
- For new persisted SwiftData entities, update the `Schema` in `AlcoholControlApp`.
- Do not duplicate business logic between `Views` and `Services`; keep calculations in services.

## 7. Testing expectations for changes

- High-risk regression zones: BAC/recovery calculations.
- High-risk regression zones: morning risks and weekly safety analytics.
- High-risk regression zones: notification scheduling/cancel.
- High-risk regression zones: app <-> widget/watch data exchange via App Group.

Minimum for a PR with logic changes:
- Build the affected scheme.
- Add one test that covers the changed behavior branch (if calculations/services are touched).

## 8. Do not change without a separate request

- Do not change bundle identifiers / entitlements / App Group ID.
- Do not rename subscription product IDs.
- Do not delete localizations or string keys.
- Do not change CSV/JSON export formats if it can break backward compatibility.

## 9. Documentation and terminology

- Keep terminology consistent across README and in-app copy (for example: "morning check-in", "weekly safety analytics", "Live Activity", "Apple Health (HealthKit)").
- Use "weekly safety analytics" for the analytics screen and "weekly summary" for the shareable summary text.
- If you introduce a new concept, update README and any relevant in-app strings together.
