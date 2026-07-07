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

After the first app launch, say **"Log meal in MacroLog"** (or "…to MacroLog").
Siri asks "What did you eat?", captures the raw text, and hands it straight to the
app — no Siri-side disambiguation. The app parses it and, if anything is too vague
to log ("a bag of popcorn", "a Chobani", "some rice"), shows a tap-only
clarification card with 2-4 concrete interpretations, a "type it instead" fallback,
and a "keep as I said it" escape hatch. Nothing is written to SwiftData until every
item is resolved. `LogMealIntent` is also available as a building block in the
Shortcuts app, where the meal text can be piped in from other actions.

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

Search-result nutrients from FoodData Central are per 100 g; the matcher's job is
picking the right entry and the right gram weight:

- **Candidate selection** ranks by: brand mention in the query ("Chobani…") →
  unit compatibility (discrete units prefer entries with a real package serving
  like "1 slice" = 15 g) → unit-aware data-type priority (Branded > Survey >
  SR Legacy for discrete/serving units; Survey (FNDDS) > SR Legacy > Branded for
  explicit weights/volumes, since branded per-100g data is often dry/raw) →
  name-overlap score.
- **Gram resolution**: weights are exact; volumes and discrete units use the
  matched entry's package serving or the USDA detail record's `foodPortions`
  ("1 cup, cooked" = 158 g) before falling back to approximations. Inherently
  discrete items with no real per-piece weight are never silently scaled at
  100 g — they're flagged low confidence instead.
- **Plausibility checks** run on every match: calories vs. Atwater (4P+4C+9F)
  within 15%, physical energy-density bounds, macro mass ≤ food mass, and
  per-unit calorie sanity bounds by unit size category (a "slice" can't be
  300 kcal). Any flag forces `matchConfidence = "low"` (⚠️ badge).

Settings → Developer → **Match diagnostics** shows the full trace for every
lookup: transcript → parsed item → all candidates with scores → selection reason
→ gram basis → flags. The same trace goes to the console via os.Logger
(subsystem `com.alexnovak.macrolog`).
