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

## Siri & voice capture

Three ways in, one screen. Say **"Log meal in MacroLog"** (Siri opens straight
to voice capture), or use the **mic** / **camera** buttons on the Meals tab, or
just type. `CaptureView` handles all of it and shows the review inline — there
is no separate review screen and no "here's what I heard" confirm step.

- **Voice**: SFSpeechRecognizer + AVAudioEngine start immediately (mic + speech
  permissions on first use), a pulsing mic shows the live transcript, and it
  auto-stops after ~2 s of silence (or tap Done). Recognition is biased toward
  food vocabulary — brands like Chobani, proteins, units — via `contextualStrings`.
- **Scan Label**: photograph a nutrition facts label; the image goes to Claude
  (vision) which reads calories/protein/carbs/fat and serving size straight off
  the label. Label data is authoritative, so USDA lookup is skipped.
- **Type**: the text field routes through the same flow.

The captured transcript (or label) runs through Claude parsing and USDA lookups
in place (brief loading state), then the **same screen** transitions to review:
the transcript collapses to a small reference line and one card animates in per
item, each showing the matched food and macros with ✅ Confirm / ✏️ Edit
(pre-filled) / 🔍 Search-a-different-match actions. Vague items carry
tap-to-resolve chips; low-confidence cards auto-open in Edit and unmatched cards
in Search. **Save All** unlocks only once every item is confirmed or edited —
nothing is written to SwiftData before that, and failed matches are never
silently saved as zero-calorie entries.

Item names are cleaned to the product name only ("I drank one can of celsius" →
"celsius"), never the raw sentence. USDA lookups retry progressively simpler
queries (full phrase → brand + product → product → brand). When you correct a
match via Search, the mapping (phrase → USDA food) is **remembered** so the next
log of that phrase reuses your correction instead of re-running the same search.

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

### Water & history

Water is tracked separately, in fluid ounces, with its own goal (Settings →
Daily targets → Water). Say "a bottle of water" / "24 oz of water" / "two
glasses of water" and it's converted to ounces (`WaterConversion`: bottle =
16 oz, glass/cup = 8 oz, can = 12 oz, plus ml/L/pint/quart/gallon; unknown
units default to a glass) and added to the Today water ring — water items skip
USDA and never count calories. On the review card a water item shows its
ounces and can be edited directly (Edit → Water (oz)). The **History** tab
lists every day you've logged, newest first, with that day's
calorie/protein/carb/fat/water totals; tap a day to see and **edit or delete**
its meals (same editor as Today).

**Spoken macros override the lookup.** If you state numbers — "chicken, 64
grams of protein, 60 grams of carbs, 25 grams of fat" — those are used directly
instead of a USDA match (calories derived from the macros if you don't say a
calorie number).

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
