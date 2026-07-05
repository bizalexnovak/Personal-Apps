# MacroLog

Voice-first macro tracker for iOS 17+. Describe a meal in plain English — via Siri
("Log meal in MacroLog") or by typing — and the app parses it with the Claude API,
looks up nutrition in USDA FoodData Central, and saves it with SwiftData.

## Getting started

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd MacroLog
xcodegen generate
open MacroLog.xcodeproj
```

Then select your development team under Signing & Capabilities and run on a device
or simulator. Run the unit tests with **⌘U** (they use mocks and in-memory SwiftData —
no network or API keys needed).

On first launch the app asks for:

- **Claude API key** (required) — create one at console.anthropic.com
- **USDA API key** (optional) — the free public `DEMO_KEY` is used until you add
  your own free key from [api.data.gov](https://api.data.gov)

Both keys are stored in the iOS Keychain, never in UserDefaults.

## Siri

After the first app launch, say **"Log meal in MacroLog"**. Siri asks "What did you
eat?", runs the full pipeline in the background, and speaks back an item/calorie
summary. `LogMealIntent` is also available as a building block in the Shortcuts app,
where the meal text can be piped in from other actions.

## Architecture

```
raw text ─▶ ClaudeMealParsingService ─▶ [FoodItemRequest] ─▶ USDANutritionLookupService ─▶ Meal + [FoodItem] ─▶ SwiftData
                 (Anthropic Messages API,                        (FoodData Central search,
                  claude-sonnet-4-6)                              match + scale to quantity)
```

- **Models/** — `Meal` and `FoodItem` (SwiftData), `FoodItemRequest` (Claude wire model),
  shared `ModelContainer` used by both the app and the intent.
- **Services/** — parsing, nutrition lookup, Keychain, and `MealLoggingService`
  which orchestrates the pipeline for both Siri and the in-app UI. Parsing and
  lookup are behind protocols (`MealParsing`, `NutritionLookup`) so tests inject mocks.
- **Intents/** — `LogMealIntent` + `MacroLogShortcuts` (App Intents / Siri phrases).
- **Views/** — Home (daily totals vs. targets), Meals (log + expandable list),
  Edit Meal (adjust quantity, swap USDA match, manual macro override), Settings, Onboarding.

### Matching heuristics

Nutrition values from FoodData Central are per 100 g. Quantities are converted to
grams with a unit table (weights exact; volumes via water density). Count-like units
("2 large", "1 slice") fall back to an assumed 100 g per piece and the item is
flagged `matchConfidence = "low"` — shown with a ⚠️ badge — so you can fix it in the
edit screen. A low name-overlap score between what you said and the matched USDA
description also flags the item.
