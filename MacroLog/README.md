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

Three ways in, one screen. Say **"Log meal in MacroLog"**, **"Log drink in
MacroLog"** (both open voice capture; the parser handles food, water, and other
drinks), or **"Scan a label in MacroLog"** (opens the camera), or use the
**mic** / **camera** buttons on the Meals tab, or just type. Items can be
renamed and portion-scaled with a **slider** (1× centred; drag left to shrink,
right to grow, roughly ¼×–4×) on the review card and in the meal editor — handy
for repeat meals where the portion differs (half a pepper, two scoops).
`CaptureView` handles all of it and shows the review inline — there is no
separate review screen and no "here's what I heard" confirm step.

- **Voice**: SFSpeechRecognizer + AVAudioEngine start immediately (mic + speech
  permissions on first use), a pulsing mic shows the live transcript, and it
  auto-stops after ~2 s of silence (or tap Done). Recognition is biased toward
  food vocabulary — brands like Chobani, proteins, units — via `contextualStrings`.
- **Scan Label**: photograph a nutrition facts label; the image goes to Claude
  (vision) which reads calories/protein/carbs/fat and serving size straight off
  the label. Label data is authoritative, so USDA lookup is skipped. The product
  name is rarely on the facts panel, so right after the scan the app opens
  **voice capture asking you to say the name** ("it's a Quest bar" → "Quest
  bar"); the spoken name is paired with the label's macros before the review
  card appears. You can tap **Skip** to fall back to whatever text the scan read.
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
- **Views/** — Today (day-by-day diary), Meals (log + expandable list),
  Edit Meal (adjust quantity, swap USDA match, manual macro override), Trends
  (multi-day chart), Settings (Profile / Daily goals / API keys / Developer
  sub-screens), Onboarding.

### The Today diary

The **Today** tab is a day-by-day diary (MyFitnessPal-style). Chevrons in the
nav bar step **back and forward through days** (never into the future; a
**Today** button jumps back to the current day), and **tapping the date opens a
calendar** to jump straight to any past day. For the selected day it shows
**calories vs. goal as a bar**, then **protein / carbs / fat / water as
circular progress rings** (consumed in the centre, goal underneath), a **"When
you ate" hourly chart** (calories by the clock hour you logged them), and that
day's **meals — tap to edit, swipe to delete**.

### Water & trends

Water is tracked separately, in fluid ounces, with its own goal (Settings →
Daily targets → Water). Say "a bottle of water" / "24 oz of water" / "two
glasses of water" and it's converted to ounces (`WaterConversion`: bottle =
16 oz, glass/cup = 8 oz, can = 12 oz, plus ml/L/pint/quart/gallon; unknown
units default to a glass) and added to the Today water ring — water items skip
USDA and never count calories. On the review card a water item shows its
ounces and can be edited directly (Edit → Water (oz)). The **Trends** tab is a
**multi-day chart** (Swift Charts): one line per nutrient —
calories/protein/carbs/fat/water — plotted as a percent of its daily goal per
day, with 1W/1M/3M/6M/1Y/All range toggles, a dashed 100%-goal reference line, and a
tappable legend below that doubles as the per-nutrient **average per day** and a
**show/hide toggle** for each line. Plotting % of goal keeps all
five differently-scaled lines on one comparable axis (no dual axes). Colours are
chart-tuned shades of the app's macro palette, CVD-validated, with distinct
point symbols per line so the series are distinguishable without relying on
colour. To see or edit a specific day's meals, use the day navigation on the
Today tab.

**Spoken macros override the lookup.** If you state numbers — "chicken, 64
grams of protein, 60 grams of carbs, 25 grams of fat" — those are used directly
instead of a USDA match (calories derived from the macros if you don't say a
calorie number).

### Micronutrients

Beyond the four headline macros, each entry also records **micronutrients** —
the fat breakdown (saturated / trans / mono- / polyunsaturated), the carb
breakdown (fiber / total & added sugars), plus cholesterol, sodium, potassium,
calcium, iron, and vitamins A/C/D. These come from USDA FoodData Central (which
returns them per food) and from scanned labels, and they **scale with the
portion** just like the macros. They're deliberately kept off Home and the
Trends chart — recorded quietly with every entry and viewable, read-only, under
**Micronutrients** in the meal editor (`Micronutrients` is stored on each
`FoodItem` as JSON, so more fields can be added later without a schema
migration).

### Recommended goals from body metrics

Settings → **Body & goal** takes your height, weight, age, sex, and activity
level and estimates the calories to hit your goal using the Mifflin-St Jeor
equation (BMR × activity multiplier). **Maintain** is the default (keeps your
current weight); **Lose** trims ~500 kcal/day and **Gain** adds ~300. The
**Recommended daily goals** section shows the resulting calories, a 30% protein
/ 40% carbs / 30% fat macro split, and a water target of about half your body
weight in ounces (`GoalCalculator`). Tap **Apply to my targets** to copy those
into the Daily targets used by the Today rings and History chart — or ignore
them and set targets by hand.

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
