# MacroLog Privacy Policy

_Last updated: July 2026_

MacroLog is a nutrition tracker. This policy explains what data the app
handles and where it goes.

## What stays on your device

- **Your food diary** — meals, ingredients, macros, micronutrients, water,
  recipes, goals, and profile details (name, height, weight, age) are stored
  **only on your iPhone**, in the app's local database. They are not uploaded
  to any server operated by us and are not shared with third parties.
- **Voice input** is transcribed on your device when your iPhone supports
  on-device speech recognition. (If on-device recognition is unavailable,
  Apple's speech service may process the audio, per Apple's own privacy
  terms.)

## What leaves your device

To understand a meal description or photo, the app sends the **minimum needed
for that one request**:

- The **text of the meal description** you typed or spoke, or the **photo**
  of a nutrition label or dish you deliberately captured, is sent to
  Anthropic's Claude API for analysis — either directly (if you use your own
  API key) or via the app operator's proxy server (if you use an invite
  code).
- **Food names** are sent to the USDA FoodData Central database (a U.S.
  government service) to look up nutrition facts.
- **Recipe search terms** are sent to the recipe providers you use
  (TheMealDB, and Spoonacular/Edamam if you configured them).

None of these requests include your name, profile, goals, or diary history.

## Invite-code usage metering

If you use an **invite code**, the proxy server records — per code —
request counts, token counts, and estimated cost, so the operator can manage
capacity. It does **not** store your meal text or photos; requests pass
through and are not retained by the proxy.

## Keys and credentials

API keys and invite codes are stored in the iOS **Keychain** on your device.

## Notifications

Optional end-of-day reminders are scheduled locally on your device. No
notification data leaves your phone.

## Data deletion

Deleting the app deletes your diary and all local data. If you used an invite
code, ask the operator to delete your code and its usage counters.

## Children

MacroLog is not directed at children under 13.

## Contact

Questions: contact the person who shared MacroLog with you, or open an issue
on the project repository.
