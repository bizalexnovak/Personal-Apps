# MindLog

Voice-first mental health tracker for iOS 17+ — the mind-side sibling of
Foob. Speak (or type) diary entries, check in on your mood, and give
yourself credit for the things that actually help — meditating, breathing,
walking, calling a friend. Everything stays on the phone: **no account, no
server, no API keys**.

## Getting started

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd MindLog
xcodegen generate
open MindLog.xcodeproj
```

Then select your development team under Signing & Capabilities and run on a
device or simulator. Run the unit tests with **⌘U** (pure logic + in-memory
models — no network, no keys, no special setup).

## The two halves

The app is built around the user's framing of mental health work:

1. **A diary you talk to** — get what's in your head out of it, and notice
   how you've been feeling.
2. **Doing something about it** — practices that are known to help, tracked
   so the effort is visible and the payoff shows up in your own data.

### 1. The voice journal

The **Journal** tab is a capture surface first: a pulsing mic you tap and
just talk to. Recognition is tuned for journaling, not command capture:

- **Long pauses are fine.** Auto-stop waits ~4 s of silence (vs the ~2 s a
  command capture would use), because people stop to think mid-entry. Tap
  **Done** to finish sooner, **Cancel** to bail.
- **Dictation punctuation is on** and the task hint is long-form dictation,
  so entries read like prose.
- **Recognition is biased toward feeling words** ("overwhelmed", "grateful",
  "burned out", "box breathing"…) via `contextualStrings`.
- **On-device recognition is preferred** whenever the locale supports it —
  the private path; words never leave the phone. If the locale's on-device
  model isn't actually installed, the app falls back to Apple's server
  recognizer for that run (same fallback dance Foob uses).

Nothing is saved while you speak. The transcript lands in a **review editor**
— fix any mis-hearings, optionally attach a **mood** (1–5 emoji scale), then
**Save**. A keyboard path ("Type instead") goes through the same review, and
the whole timeline of past entries lives below the mic, grouped by day. Tap
any entry to read, edit, re-date, or delete it.

**Mood check-ins** are the zero-effort version: one emoji tap on the Today
tab records a timestamped mood with no writing required. Check-ins and
written entries share one model (`JournalEntry`) so the diary reads as a
single timeline.

**Sentiment, on device.** At save time each entry gets a sentiment score
(-1…1) from Apple's NaturalLanguage framework — no network involved. It's
deliberately a *soft* signal: a tentative "sounds like a rough one" hint on
the review screen and an optional overlay on the mood chart. Your own 1–5
rating always outranks it.

### 2. The practice score

The Today ring shows a daily **practice score (0–100)** — how much you did
for your mind today. Scoring measures **actions, not outcomes** on purpose: a
hard day where you still meditated and journaled scores well, because that's
the behaviour worth reinforcing. (Mood is tracked separately, and the two are
only *related* in Trends.)

- Each activity earns **points per minute** with a **daily cap** — short,
  potent practices (gratitude, breathwork) earn fast but cap early; long,
  gentle ones (a screen break) earn slowly but run longer. Caps are what make
  variety beat grinding: three hours of one thing can't max a day.
  Example: 30 min of meditation = 36 points.
- **Journaling adds 15**, a **mood check-in adds 5** — the diary habits count
  as practice too.
- The built-in catalog (`ActivityCatalog`): meditation, breathing, exercise,
  time outside, social time, gratitude, reading, screen break, therapy,
  creative time — each with a one-line "why this helps" shown when logging.
- The **daily goal** (default 50 ≈ one real practice + a journal entry) is
  adjustable in Settings; the ring, reminders, and the Trends goal line all
  follow it.

Logging is two taps on the **Practice** tab (activity → duration preset), and
past days can be backfilled from the Today tab's day navigation.

### Guided practice (the app helps, not just counts)

The Practice tab can *run* the two practices that work well guided:

- **Guided breathing** — box (4-4-4-4), 4-7-8, and coherent (5½-5½)
  patterns, animated as a circle that grows and shrinks with your breath,
  with step labels and a soft haptic on each transition. The pattern math
  (`BreathingPattern.position/scale`) is pure and unit-tested.
- **Meditation timer** — pick a duration, the screen stays awake, pause and
  resume as needed.

Both **log themselves** when the session ends (finish or "End session" keeps
the minutes; ✕ discards), so doing the practice and getting credit are the
same action.

### Trends & insights

The **Trends** tab charts (Swift Charts, 1W/1M/3M/1Y/All ranges):

- **Mood** over time (1–5, emoji axis), with an optional on-device
  **writing-sentiment overlay**.
- **Practice score** per day against the goal line.
- **Activity minutes** per day, stacked by activity.
- Streak / best-streak / entry-count / total-minutes stat tiles.

**Insights** relate effort to outcome, entirely on device
(`InsightsEngine`): *"On days with meditation, your mood has averaged 0.8
higher"*, journaling lift, week-over-week mood movement, and streak
celebrations. Comparisons only appear once both sides have ≥ 3 rated days —
no invented patterns from thin data — and the wording stays descriptive
("your averages differ"), never diagnostic.

### Reminders

Settings → Reminders configures daily nudges (mood check-in / journal /
practice) with custom times and messages. They're **goal-aware**: whenever
the app foregrounds or backgrounds it reschedules, and today's fire is
skipped if the habit is already done — a check-in reminder stays quiet on
days you've checked in. Six future days are always scheduled so nudges keep
firing even if the app isn't opened for a while.

## Privacy stance

Mental-health data is the most sensitive thing a personal app can hold, so
the v1 line is simple: **everything stays on the phone.**

- Entries, moods, and activity logs live in SwiftData on device.
- Sentiment analysis is Apple's on-device NaturalLanguage framework.
- Speech recognition prefers the on-device engine (see above for the one
  fallback case).
- No analytics, no account, no network calls anywhere in the app.
- `PrivacyInfo.xcprivacy` declares zero collected data / zero tracking.

The Settings screen says this in plain words, alongside a note that the app
is a self-reflection tool, not a medical device (with the US 988 lifeline
mentioned).

## Architecture

```
mic ─▶ SpeechCaptureController ─▶ transcript ─▶ review (edit + mood) ─▶ JournalEntry ─▶ SwiftData
        (on-device SFSpeech,                        │
         journaling-tuned)                          └▶ SentimentAnalyzer (on-device NL)

ActivityLog ─▶ PracticeScore (points/min + daily caps + bonuses) ─▶ Today ring
JournalEntry + ActivityLog ─▶ DayAggregator ─▶ [DaySummary] ─▶ InsightsEngine ─▶ Trends
```

- **Models/** — `JournalEntry` (voice/typed/check-in in one timeline),
  `ActivityLog`, the fixed `ActivityCatalog`, shared `ModelContainer`.
- **Services/** — speech capture, sentiment, scoring, day aggregation,
  insights, breathing patterns, the practice session timer, reminders. The
  scoring/insights/breathing layers are pure value-type logic so the tests
  never need a database or a device.
- **Views/** — Journal (capture + timeline), Today (day-by-day dashboard
  with chevron/calendar navigation like Foob's diary), Practice
  (guided sessions + two-tap logging), Trends, Settings, Onboarding.
- **Theme** — same system as Foob: Light / Dark / Auto (time-of-day) /
  Custom appearance, customizable app accent + background + chart colours,
  all in AppStorage and injected via the environment. Default is dark with
  a calm teal accent.

The five tabs share Foob's shell: the keep-alive `ZStack` tab container,
the floating glassy tab bar, and a "+" quick-actions menu (voice entry /
type entry / log activity / breathe / meditate).

## Roadmap

- **HealthKit** — import Mindful Minutes and sleep; export sessions.
- **Home-screen widget** — today's score ring + one-tap check-in (App Group
  plumbing mirrors Foob's widget).
- **Optional Claude-powered weekly reflection** — a gentle summary of the
  week's entries via the same invite-code proxy Foob uses. Off by
  default and clearly opt-in, because it means journal text leaving the
  device; the on-device experience must stay complete without it.
- **Custom activities** — user-defined catalog entries (needs a stored
  catalog so scores stay comparable).
- **Export** — encrypted backup / plain-text export of the journal.
