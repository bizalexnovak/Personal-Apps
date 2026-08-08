#!/usr/bin/env bash
#
# Push the current source straight onto the phone over Wi-Fi.
#
# After one cabled install (which is what tells the Mac and the phone about each
# other), this is the whole update loop: regenerate the project, build Release,
# install over the network, launch. No cable, no TestFlight, no waiting on
# App Review.
#
#   bash bin/deploy-phone.sh              # first device found, or $DEVICE_NAME
#   DEVICE_NAME="Nova" bash bin/deploy-phone.sh
#
# Running it twice in a row is harmless — the install replaces the app in place
# and the launch terminates any running copy first.

set -euo pipefail

# ---- per-app settings (the only lines that differ between apps in the fleet) --
APP_NAME="MindLog"
SCHEME="MindLog"
BUNDLE_ID="com.alexnovak.MindLog"
# ------------------------------------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/deploy-phone"
SIGNING_XCCONFIG="$PROJECT_DIR/Signing.xcconfig"
DEVICE_NAME="${DEVICE_NAME:-}"

cd "$PROJECT_DIR"

die() {
  echo "" >&2
  echo "deploy-phone: $1" >&2
  shift
  for line in "$@"; do
    echo "  $line" >&2
  done
  echo "" >&2
  exit 1
}

step() { echo "==> $*"; }

# --- 0. tooling -----------------------------------------------------------------
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found." \
  "Install Xcode from the App Store, then run:" \
  "  sudo xcode-select -s /Applications/Xcode.app"

xcrun devicectl --version >/dev/null 2>&1 || die "xcrun devicectl not available." \
  "devicectl ships with Xcode 15+ and is what talks to iOS 17+ devices." \
  "Update Xcode, then run: sudo xcode-select -s /Applications/Xcode.app"

# --- 1. signing -----------------------------------------------------------------
# The team lives in Signing.xcconfig precisely so `xcodegen generate` can't throw
# it away. An empty value here means every device build will fail deep inside
# xcodebuild with a much less obvious error, so check it up front.
TEAM_ID=""
if [ -f "$SIGNING_XCCONFIG" ]; then
  TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$SIGNING_XCCONFIG" | tr -d '[:space:]')"
fi

if [ -z "$TEAM_ID" ]; then
  die "signing is not configured — DEVELOPMENT_TEAM is empty." \
    "Put your 10-character Team ID in:" \
    "  $SIGNING_XCCONFIG" \
    "Find it at developer.apple.com -> Membership, or in Xcode's" \
    "Signing & Capabilities team dropdown (the code in parentheses)."
fi
step "Signing with team $TEAM_ID"

# --- 2. generate the project ----------------------------------------------------
if [ -f "$PROJECT_DIR/project.yml" ]; then
  command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found, but project.yml is present." \
    "The .xcodeproj is generated, not committed. Install it with:" \
    "  brew install xcodegen"
  step "Generating $APP_NAME.xcodeproj"
  xcodegen generate --quiet
fi

# --- 3. find the phone ----------------------------------------------------------
step "Looking for a paired device${DEVICE_NAME:+ named \"$DEVICE_NAME\"}"
DEVICES_JSON="$(mktemp -t deploy-phone-devices)"
trap 'rm -f "$DEVICES_JSON"' EXIT

# --timeout is accepted by current devicectl; retry without it rather than
# reporting a bogus "no device" if an older build doesn't know the flag.
xcrun devicectl list devices --timeout 15 --json-output "$DEVICES_JSON" >/dev/null 2>&1 \
  || xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 \
  || die "could not list devices." \
    "Open Xcode once (Window -> Devices and Simulators) so it can start the" \
    "device daemons, then try again."

# devicectl needs its own device identifier; xcodebuild wants the hardware UDID.
# Pull both in one pass, preferring a device that's actually reachable right now.
DEVICE_INFO="$(
  python3 - "$DEVICES_JSON" "$DEVICE_NAME" <<'PY' || true
import json, sys

path, wanted = sys.argv[1], sys.argv[2].strip().lower()
try:
    devices = json.load(open(path))["result"]["devices"]
except Exception:
    sys.exit(1)

candidates = []
for d in devices:
    props = d.get("deviceProperties", {})
    conn = d.get("connectionProperties", {})
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") not in (None, "iOS"):
        continue
    name = props.get("name", "")
    if wanted and name.strip().lower() != wanted:
        continue
    reachable = conn.get("tunnelState") in ("connected", "available")
    candidates.append((not reachable, name, d.get("identifier", ""), hw.get("udid", "")))

if not candidates:
    sys.exit(1)

# Reachable devices sort first.
candidates.sort()
_, name, identifier, udid = candidates[0]
if not identifier or not udid:
    sys.exit(1)
print("\t".join([name, identifier, udid]))
PY
)"

if [ -z "$DEVICE_INFO" ]; then
  die "no reachable iPhone found${DEVICE_NAME:+ named \"$DEVICE_NAME\"}." \
    "Wireless deploy needs a one-time cabled setup. Check, in order:" \
    "  1. The phone and this Mac are on the same Wi-Fi network." \
    "  2. The phone is unlocked (wireless pairing wakes only an unlocked phone)." \
    "  3. Settings -> Privacy & Security -> Developer Mode is ON on the phone." \
    "  4. Xcode -> Window -> Devices and Simulators, select the phone, and" \
    "     tick \"Connect via network\" — this needs the cable plugged in once." \
    "If the phone has a different name, run:" \
    "  DEVICE_NAME=\"Your iPhone\" bash bin/deploy-phone.sh" \
    "Currently visible devices:" \
    "$(xcrun devicectl list devices 2>/dev/null | sed -n '1,12p' | sed 's/^/    /')"
fi

FOUND_NAME="$(printf '%s' "$DEVICE_INFO" | cut -f1)"
DEVICE_ID="$(printf '%s' "$DEVICE_INFO" | cut -f2)"
DEVICE_UDID="$(printf '%s' "$DEVICE_INFO" | cut -f3)"
step "Using \"$FOUND_NAME\" ($DEVICE_UDID)"

# --- 4. build -------------------------------------------------------------------
step "Building $SCHEME (Release) for the device"
if ! xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build; then
  die "the build failed — see the xcodebuild output above." \
    "Scroll up to the first line containing \"error:\"; that's the real one." \
    "If it's about provisioning, open $APP_NAME.xcodeproj and check" \
    "Signing & Capabilities for the $SCHEME target once, then re-run this."
fi

APP_PATH="$BUILD_DIR/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || die "the build succeeded but $APP_NAME.app is missing." \
  "Expected it at: $APP_PATH"

# --- 5. install + launch over the network ---------------------------------------
step "Installing on \"$FOUND_NAME\" over the network"
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
  die "the install failed." \
    "Most often the phone locked mid-transfer or dropped off Wi-Fi." \
    "Unlock it, confirm it's on the same network, and run this again."
fi

step "Launching $APP_NAME"
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID" >/dev/null

echo ""
echo "Done — $APP_NAME is running on \"$FOUND_NAME\"."
