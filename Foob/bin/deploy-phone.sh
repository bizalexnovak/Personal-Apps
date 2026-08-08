#!/usr/bin/env bash
#
# Build Foob for a real iPhone and install it over Wi-Fi — no cable.
#
# The cable is only needed once, to pair the phone with this Mac and tick
# "Connect via network" in Xcode → Window → Devices and Simulators. After that
# `xcrun devicectl` reaches the phone over the local network, so every future
# update is this one command. See README.md → "Updating on your phone".
#
#   bin/deploy-phone.sh          # the only paired iPhone, or $FOOB_DEVICE
#   bin/deploy-phone.sh Nova     # by device name (or UDID)
#
# Running it twice in a row is harmless: the install replaces the app in place
# and the launch restarts it.

set -euo pipefail

FOOB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FOOB_DIR"

SCHEME="Foob"
CONFIGURATION="Release"
# Kept outside the repo (which has no .gitignore) so build products never show
# up as untracked files. Persistent, so repeat runs are incremental.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Foob-deploy-phone"
DEVICE_QUERY="${1:-${FOOB_DEVICE:-}}"

die() {
  echo "" >&2
  echo "deploy-phone: $1" >&2
  shift
  while [ $# -gt 0 ]; do echo "  $1" >&2; shift; done
  echo "" >&2
  exit 1
}

step() { echo "==> $*"; }

# --- Preflight ---------------------------------------------------------------

command -v xcodebuild >/dev/null 2>&1 || die \
  "Xcode's command line tools aren't on PATH." \
  "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app"

command -v python3 >/dev/null 2>&1 || die \
  "python3 isn't on PATH — this script uses it to read devicectl's JSON." \
  "Install Xcode's command line tools: xcode-select --install"

xcrun devicectl --version >/dev/null 2>&1 || die \
  "xcrun devicectl is missing (it ships with Xcode 15 and later)." \
  "Update Xcode, then run: sudo xcode-select -s /Applications/Xcode.app"

# The Team ID lives in Signing.xcconfig so it survives `xcodegen generate`.
# Without it a device build can't be signed, and xcodebuild's own failure for
# that is a wall of provisioning noise — so check it up front.
TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' Signing.xcconfig | tr -d '[:space:]')"
if [ -z "$TEAM_ID" ]; then
  die "signing isn't configured — DEVELOPMENT_TEAM is empty in Foob/Signing.xcconfig." \
    "Put your 10-character Team ID there (developer.apple.com → Membership," \
    "or the code in parentheses in Xcode's team dropdown):" \
    "" \
    "    DEVELOPMENT_TEAM = ABCDE12345" \
    "" \
    "Details: docs/TESTFLIGHT.md → Step 1."
fi

# --- Find the phone on the network -------------------------------------------

step "Looking for a paired iPhone"
DEVICE_JSON="$(mktemp -t foob-devices)"
trap 'rm -f "$DEVICE_JSON"' EXIT

if ! xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1; then
  die "couldn't ask Xcode for the list of devices." \
    "Open Xcode once (it may need to finish installing components), then retry."
fi

# Prints "<identifier><tab><name>" for each paired iOS device, matching
# DEVICE_QUERY against the name, UDID, or identifier when one was given.
DEVICE_MATCHES="$(DEVICE_QUERY="$DEVICE_QUERY" python3 - "$DEVICE_JSON" <<'PY'
import json, os, sys

query = os.environ.get("DEVICE_QUERY", "").strip().lower()
with open(sys.argv[1]) as handle:
    devices = json.load(handle).get("result", {}).get("devices", [])

for device in devices:
    props = device.get("deviceProperties", {})
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if hardware.get("platform") != "iOS":
        continue
    if connection.get("pairingState") not in (None, "paired"):
        continue
    name = props.get("name") or hardware.get("udid") or ""
    identifier = device.get("identifier") or hardware.get("udid") or ""
    if not identifier:
        continue
    if query and query not in (name.lower(), (hardware.get("udid") or "").lower(), identifier.lower()):
        continue
    print("%s\t%s" % (identifier, name))
PY
)"

if [ -z "$DEVICE_MATCHES" ]; then
  KNOWN="$(DEVICE_QUERY="" python3 - "$DEVICE_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    devices = json.load(handle).get("result", {}).get("devices", [])
names = [d.get("deviceProperties", {}).get("name", "?") for d in devices]
print(", ".join(names) if names else "(none)")
PY
)"
  die "no paired iPhone found${DEVICE_QUERY:+ matching \"$DEVICE_QUERY\"}." \
    "Devices this Mac can see: $KNOWN" \
    "" \
    "Check, in order:" \
    "  1. The phone is unlocked, on the same Wi-Fi as this Mac, and trusts it." \
    "  2. Settings → Privacy & Security → Developer Mode is on (iPhone)." \
    "  3. Xcode → Window → Devices and Simulators → your iPhone →" \
    "     \"Connect via network\" is ticked. That needs the cable once." \
    "" \
    "Plug the phone in and run this again to re-establish the pairing."
fi

if [ "$(printf '%s\n' "$DEVICE_MATCHES" | wc -l | tr -d ' ')" -gt 1 ]; then
  die "more than one paired iPhone — say which one." \
    "$(printf '%s\n' "$DEVICE_MATCHES" | cut -f2 | sed 's/^/  /')" \
    "" \
    "    bin/deploy-phone.sh \"Nova\""
fi

DEVICE_ID="$(printf '%s' "$DEVICE_MATCHES" | cut -f1)"
DEVICE_NAME="$(printf '%s' "$DEVICE_MATCHES" | cut -f2)"
step "Found $DEVICE_NAME"

# --- Generate + build ---------------------------------------------------------

# Foob.xcodeproj is generated and untracked, so regenerate it when we can.
if [ -f project.yml ]; then
  if command -v xcodegen >/dev/null 2>&1; then
    step "xcodegen generate"
    xcodegen generate >/dev/null
  elif [ ! -d "$SCHEME.xcodeproj" ]; then
    die "$SCHEME.xcodeproj doesn't exist and xcodegen isn't installed." \
      "Run: brew install xcodegen"
  fi
fi

build_for() {
  xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$1" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    build
}

# Build against the phone by name first: that's what lets Xcode add a
# not-yet-registered device to the provisioning profile. If the destination
# can't be resolved (phone asleep mid-run, say), fall back to a generic device
# build — the .app is identical, it just can't register a new device.
step "Building $SCHEME ($CONFIGURATION) for $DEVICE_NAME"
BUILD_LOG="$(mktemp -t foob-build)"
trap 'rm -f "$DEVICE_JSON" "$BUILD_LOG"' EXIT
BUILD_OK=yes
build_for "platform=iOS,name=$DEVICE_NAME" 2>&1 | tee "$BUILD_LOG" || BUILD_OK=no
if [ "$BUILD_OK" = no ] && grep -q "Unable to find a destination" "$BUILD_LOG"; then
  step "Couldn't target $DEVICE_NAME directly — building a generic device build"
  BUILD_OK=yes
  build_for "generic/platform=iOS" || BUILD_OK=no
fi
if [ "$BUILD_OK" = no ]; then
  die "the build failed — the full xcodebuild output is above." \
    "If it's about provisioning: open $SCHEME.xcodeproj, pick the Foob target →" \
    "Signing & Capabilities, and let Xcode register this device once" \
    "(Team $TEAM_ID must be signed in under Xcode → Settings → Accounts)." \
    "Otherwise it's a compile error — fix it and run this again."
fi

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
[ -d "$APP_PATH" ] || die \
  "the build reported success but $APP_PATH isn't there." \
  "Delete $DERIVED_DATA and run this again."

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"

# --- Install + launch over the network ----------------------------------------

step "Installing on $DEVICE_NAME over the network"
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"; then
  die "couldn't install on $DEVICE_NAME." \
    "Unlock the phone and keep it on the same Wi-Fi, then run this again." \
    "If it keeps failing, plug the cable in once to refresh the pairing."
fi

# --terminate-existing makes a second run in a row restart the app rather than
# fail on "already running". Launching is the cherry on top, though — if it
# doesn't take, the new build is already on the phone, so don't fail the run.
step "Launching $BUNDLE_ID"
if ! xcrun devicectl device process launch \
       --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" >/dev/null 2>&1 &&
   ! xcrun devicectl device process launch \
       --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "deploy-phone: installed on $DEVICE_NAME, but couldn't launch it remotely — tap Foob on the phone." >&2
  exit 0
fi

echo ""
echo "Foob is updated and running on $DEVICE_NAME."
