# References

Where MindLog's interaction patterns come from, and what we deliberately did
*not* copy. This file exists so a future change can tell an intentional
borrowing from an accident.

> **Note for the owner:** the milestone brief pointed at a fuller teardown at
> `suite-upload/refs/MINDLOG-REFERENCES.md` in the task's source folder. That
> folder was not present in the checkout this milestone was built in, so this
> file records only what was actually applied in M1. Drop the full teardown in
> here when you have it — the sections below are written to be appended to, not
> replaced.

## How We Feel — the two-step check-in

The pattern we took: **capture first, refine second.** You tap a coarse feeling
and that is *already logged*. Only then are you offered a finer vocabulary.

What that means in MindLog:

- The 1-5 mood tap saves a `JournalEntry` immediately, on the spot. Nothing
  downstream can delay or block it.
- `MoodDetailStep` (emotion words + who/what/where context tags) appears
  **after** the save, as a dismissible sheet. Swiping it away is a complete,
  correct interaction — the check-in is not "incomplete" without it.
- The emotion words shown are scoped to the mood just tapped, so the second
  step is a short relevant list rather than a wall of vocabulary.

What we did **not** take: How We Feel's social layer, its streaks, and its
push toward daily completion. MindLog rewards showing up and says nothing when
you don't.

## Competitor complaint we're answering: you can't log the past

The single loudest complaint about mood trackers is that a day you forgot to
log is a day you can never log. So in M1:

- Any entry's timestamp is editable (`JournalEntryDetailView`), within a
  one-year window that ends at "now" — see `EntryEditing`.
- The Today screen's mood card works on **any** day it is showing, not just
  today; picking a past day and tapping a mood backdates the entry to that day
  at the current time of day (`EntryEditing.backdated(toDayOf:)`).

## Widgets and notifications: capture without the app

Lock-screen and home-screen widgets (WidgetKit + AppIntents, iOS 17
interactive widgets) and the notification check-in both log **without opening
the app** — `openAppWhenRun = false` on the intent, `options: []` (not
`.foreground`) on the notification actions.

Neither of those contexts can safely open the app's SwiftData store, so both
append a `PendingCheckIn` to an App Group queue (`CheckInInbox`) which the app
drains on next foreground (`CheckInSync.drain`). The queued item carries the
**tap's** timestamp, not the drain's, so a mood logged at 11 PM is a mood
logged at 11 PM even if the app isn't opened until morning.

An App Group is a second on-device sandbox shared by two processes of the same
app. Nothing here leaves the phone; the covenant is unchanged.
