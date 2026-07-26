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

### Home-screen widget (one-time setup)

The `MacroLogWidgetExtension` target shows today's calories + macros on the home
screen. It shares data with the app through an **App Group**, which needs signing
set up once after `xcodegen generate`:

1. Select the **MacroLog** target → Signing & Capabilities → set your Team.
2. Add the **App Groups** capability and check/enter
   `group.com.alexnovak.MacroLog` (already in `MacroLog.entitlements`).
3. Select the **MacroLogWidgetExtension** target → set the **same Team** and the
   **same App Group** (`group.com.alexnovak.MacroLog`).

If you use a different group ID, update it in both `.entitlements` files and in
`Shared/DayNutritionSnapshot.swift` (`WidgetDataStore.appGroup`). Then long-press
the home screen → **+** → search **MacroLog** to add the small or medium widget.
The app refreshes it whenever the day's totals change (`WidgetCenter.reloadAllTimelines`).

On first launch the app asks how it should reach Claude — two paths
(`ClaudeEndpoint` resolves every AI request through whichever is configured):

- **Invite code** (friends & family): a short code from whoever shared the
  app. Requests go through the MacroLog proxy (`server/` — a Cloudflare
  Worker holding the operator's Claude key), which also **meters each
  person's tokens and estimated cost per month** for capacity/pricing
  decisions and enforces a monthly per-person spend cap. Bake the deployed
  Worker URL into `ClaudeEndpoint.defaultProxyURL` so testers only ever type
  their code. Setup: `server/README.md`.
- **My own API key** (developer path): a Claude key from
  console.anthropic.com, used directly against Anthropic. Optionally a
  **USDA API key** — the free public `DEMO_KEY` is used until you add your
  own free key from [api.data.gov](https://api.data.gov).

Codes and keys are stored in the iOS Keychain, never in UserDefaults.

**Distributing to testers:** see `docs/TESTFLIGHT.md` for the full
enroll → archive → TestFlight walkthrough (and why free-signed builds stop
launching after 7 days), plus `docs/privacy-policy.md` ready to host for the
external-testing requirement. `MacroLog/PrivacyInfo.xcprivacy` (required
privacy manifest) ships in the app target.

## Siri & voice capture

Capture happens on the **Log** tab, inline — no modal. It's voice by default
(a pulsing mic you tap to start recording on that same screen), with a
camera-app-style **Voice / Scan** switch and a keyboard button to type. A **"+"** button beside the tabs (Today / Trends) on a custom bottom bar opens
a mini menu (Voice / Scan / AI / Type) that jumps to the Log tab in the chosen
mode. Siri (**"Log meal in MacroLog"**, **"Log drink in MacroLog"**, **"Scan a
label in MacroLog"**) opens the same flow modally via `CaptureView`. Items can
be renamed and portion-scaled with a **`PortionSliderView`** — a slider that
snaps toward ½× / 1× / 2× / 5× / 10× (with tick marks) plus a **type-in field**
for an exact multiplier — on the review card and in the meal editor. Everything
shows the review inline — no separate review screen and no "here's what I heard"
step. The review's **Date** row (defaults to today) back-dates a meal to a
previous day.

- **Voice**: tap the pulsing mic to start (mic + speech permissions on first
  use); it pulses idly before you start and with your voice while listening,
  shows the live transcript, and auto-stops after ~2 s of silence (or tap Done).
  Recognition is biased toward food vocabulary — brands like Chobani, proteins,
  units — via `contextualStrings`. (`CaptureComponents` holds the shared pulse /
  listening / review pieces used by both the Log tab and the Siri screen.)
- **Scan Label**: a **live scanner** (`LiveLabelScannerView`) reads the camera
  feed with on-device Vision text recognition and **auto-captures the frame as
  soon as it recognizes a nutrition or supplement facts label** ("Nutrition
  Facts", "Supplement Facts", "Calories", "Serving…", vitamin/creatine/caffeine
  wording) — no shutter (tap to grab it manually as a fallback). That frame
  goes to Claude (vision) which reads calories/protein/carbs/fat, micronutrients,
  and serving size straight off the label; label data is authoritative, so USDA
  lookup is skipped. The product name is rarely on the facts panel, so right
  after the capture the app opens **voice capture asking you to say the name**
  ("it's a Quest bar" → "Quest bar") before the review card appears. Tap
  **Skip** to fall back to whatever text the scan read.
- **Dish photo**: a separate mode from label scanning — photograph a *prepared
  meal* and Claude (vision) estimates each component's portion and macros
  (`DishEstimationService`). Because these are estimates, every item comes back
  low-confidence with its card open for you to confirm or adjust.
- **Type**: the keyboard button (or the "+" menu's Type) routes through the same flow.

**Quick add.** The Log tab's idle screen shows one-tap chips for items you log
often (`MealSuggestions` groups history by name + unit and keeps repeats
logged ≥ 2×). Ranking is **time-of-day aware**: logs within ±2 h of the
current clock time count double on top of overall frequency, so mornings lead
with your usual breakfasts and evenings with your usual snacks. Tapping a chip
re-logs a copy with its last-known macros and micronutrients immediately — no
parsing or lookup.

**Recipes.** The **Recipes** tab keeps reusable meal templates: save any
logged meal as a recipe from the meal editor ("Save as recipe"), or build one
by hand (+ → name → add ingredients with their macros). Opening a recipe shows
its ingredients and totals; **"Log this recipe today"** stamps a fresh copy
into the diary as a normal meal. The meal editor also has **"Log this meal
again today"** for one-off repeats without saving a recipe. A **starter
library** of common recipes (spread across breakfast/lunch/dinner/snack) is
seeded once on first launch, so the tab is useful before you've saved anything.

**Recommended for now.** The top of the Recipes tab ranks recipes for the
current moment (`RecipeRecommender`) by three signals:

- **Time of day** — breakfast-y recipes in the morning, dinners in the evening
  (each recipe carries a *meal slot* you can change in its detail view).
- **Macro gaps** — as the day fills in, recipes heavy in whatever macro is
  furthest from its goal rise (short on protein but near your carb/fat goals →
  protein-heavy recipes get promoted). At the start of the day, with nothing
  logged, this is neutral and time of day leads.
- **Preference** — recipes you log more often (and recently) drift up over
  time, so the list learns your favourites.

Each suggestion shows why ("Dinner · high protein") and has a one-tap log.

**Recipe search.** The magnifying glass on the Recipes tab searches the web and
imports a result as a recipe. It queries every configured provider at once:
**TheMealDB** (free, always on, no key — searched by name, then by ingredient
when the name search finds nothing), plus **Spoonacular** and **Edamam** if you
add their free API keys under Settings → API keys. **Without those keys the
searchable library is only TheMealDB's ~300 recipes — a Spoonacular key takes
it to 350k+ with per-ingredient nutrition, so add one early.** Imports are
scaled to a single serving; when a source doesn't include nutrition, each
ingredient's macros are filled from the USDA lookup the app already uses.

**Instructions.** Recipes carry optional preparation steps, shown and editable
in the recipe's detail view — deliberately empty for things that need none (a
protein bar, a fast-food item). The seeded library includes steps for all its
cooked recipes; imports bring them along when the source has them (TheMealDB's
full steps, Spoonacular's numbered analyzed steps) and Edamam links to the
original recipe page instead (its API doesn't include steps).

**Offline / bad reception.** Logging never requires a connection. Speech
recognition runs **on device** (when the locale supports it), and if the
Claude parse can't reach the network the transcript is parsed by an on-device
fallback (`LocalMealParser`) instead — water, bare supplements, spoken macro
numbers, and previously-corrected foods (`RememberedMatchStore`) all resolve
fully offline; anything else appears as an unmatched card you complete by hand
with **Edit** (typed macros save normally). A banner on the review screen says
when this happened. Quick add always works offline. Network calls fail fast
(12–30 s timeouts instead of the 60 s system default), so a dead zone means a
quick fallback, not a hanging spinner. Label scanning and dish photos do need
the network (the image goes to Claude vision).

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
- **Views/** — Today (day-by-day diary), Log (voice/scan/type capture surface),
  Edit Meal (adjust quantity, swap USDA match, manual macro override, re-log,
  save as recipe), Recipes (saved meal templates, one-tap re-log), Trends
  (multi-day chart), Settings (Profile / Daily goals / Appearance / API keys /
  Developer sub-screens), Onboarding.
- **Theme** — four appearance modes: **Light**, **Dark**, **Auto** (flips
  light/dark by time of day, ~7am–7pm, re-evaluated on a minute timer), and
  **Custom** (uses a customizable background colour, with text auto-switching to
  light/dark based on the colour's luma). Plus a customizable **app accent**
  (buttons, active tab, capture controls, the "+") and a customizable
  five-colour **metric palette**. All stored in AppStorage and injected through
  the environment (`appAccent`, `appBackground`, `MetricPalette`) so the UI,
  Today rings/bar, and Trends chart update live; Settings → Appearance edits
  them. Default is Dark.

### The Today diary

The **Today** tab is a day-by-day diary (MyFitnessPal-style). Chevrons in the
nav bar step **back and forward through days** (never into the future; a
**Today** button jumps back to the current day), and **tapping the date opens a
calendar** to jump straight to any past day. For the selected day it shows
**calories vs. goal as a bar**, then **protein / carbs / fat / water as
circular progress rings** (consumed in the centre, goal underneath), a **"When
you ate & drank" hourly chart** (calories and water as two side-by-side bars by
the clock hour, each drawn as that hour's share of its daily goal so both read
on one axis), and that day's **meals — tap to edit (including the logged date &
time), swipe to delete**.

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

### Micronutrients, caffeine & supplements

Beyond the four headline macros, each entry also records **micronutrients** —
the fat breakdown (saturated / trans / mono- / polyunsaturated), the carb
breakdown (fiber / total & added sugars), cholesterol, sodium, potassium,
minerals (calcium, iron, magnesium, zinc, phosphorus, copper, manganese,
selenium), vitamins (A, C, D, E, K, B1/B2/B3/B6/B12, folate), plus **caffeine**
and **creatine**. These come from USDA FoodData Central (which returns them per
food — coffee and energy drinks carry their caffeine), from scanned nutrition
*and supplement* facts labels, and they **scale with the portion** just like
the macros. Bare supplements can be logged directly — "5 g of creatine" or "a
caffeine pill" skips USDA (a food search would mismatch them) and records the
dose as a zero-calorie entry (`SupplementConversion`). Kept off the Trends
chart, they're viewable read-only in two places: per item under
**Micronutrients** in the meal editor, and summed for the day in a collapsed
**Micronutrients** section at the bottom of the Today tab (`Micronutrients` is
stored on each `FoodItem` as JSON, so more fields can be added later without a
schema migration).

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
