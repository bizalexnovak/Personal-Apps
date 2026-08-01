# MacroLog Privacy Policy

_Last updated: August 2026_

> The live copy of this policy — the one App Store Connect links to — is
> served by the proxy server at `/privacy` (see `server/worker.js`,
> `PRIVACY_HTML`). **Edit both together.**

MacroLog is a nutrition tracker. This policy explains what data the app
handles and where it goes.

## What stays on your device

Your food diary — meals, ingredients, macros, micronutrients, water,
recipes, goals, and profile details — is stored only on your iPhone. It is
not uploaded to any server operated by us and is not shared with third
parties. Voice input is transcribed on your device when your iPhone
supports on-device recognition; when it does not (or on-device recognition
fails), Apple's speech service may process the audio, under Apple's own
privacy terms.

## What leaves your device

To understand a meal, the app sends the minimum needed for that one
request: the text of the meal description or a photo you deliberately
captured is sent to Anthropic's Claude API for analysis (directly with
your own key, or via the operator's proxy with an invite code). Food names
are sent to USDA FoodData Central and, when needed, Open Food Facts to
look up nutrition. Recipe search terms go to the providers you use. None
of these requests include your name, profile, goals, or diary history.

## Shared community features

If you use an invite code: scanned nutrition labels you capture (product
name, serving, nutrition numbers — never your diary) may be contributed to
a shared food database; suggestions, votes, and comments you post on the
community board are visible to other users with your display name; the
proxy records per-code request counts, token counts, and estimated cost
for capacity management. Meal text and photos are not retained by the
proxy.

## Keys and credentials

API keys and invite codes are stored in the iOS Keychain on your device.

## Data deletion

Deleting the app deletes your diary and all local data. Ask the operator
to delete your invite code — doing so also removes your usage counters,
your votes, and your comments, and detaches your name from suggestions you
posted.

## Children

MacroLog is not directed at children under 13.

## Contact

Contact the person who shared MacroLog with you.
