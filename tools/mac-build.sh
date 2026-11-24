#!/bin/bash
# Builds Bedtime or Bust on a Mac and launches it in the iOS Simulator.
#
#   tools/mac-build.sh             check tools, test the engine, build, launch
#   tools/mac-build.sh --no-launch stop after the build
#
# Each step stops with the exact command to fix it. The full output goes to
# build/mac-build.log; if a step fails, paste the error lines it prints.
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

LAUNCH=1
[ "${1:-}" = "--no-launch" ] && LAUNCH=0

BUNDLE_ID=com.example.bedtimeorbust # matches project.yml
DERIVED=build/DerivedData
APP="$DERIVED/Build/Products/Debug-iphonesimulator/BedtimeOrBust.app"
LOG=build/mac-build.log
mkdir -p build
: >"$LOG"

step() { printf '\n==> %s\n' "$*" | tee -a "$LOG"; }
fail() {
  printf '\nFAILED: %s\n' "$1"
  [ -n "${2:-}" ] && printf 'Fix: %s\n' "$2"
  printf 'Full log: %s/%s\n' "$PWD" "$LOG"
  exit 1
}
# Known first-run problems, matched in the log, with their fixes.
hint() {
  if grep -q "agreed to the Xcode license" "$LOG"; then echo "sudo xcodebuild -license accept"
  elif grep -qi "runFirstLaunch\|first launch" "$LOG"; then echo "xcodebuild -runFirstLaunch"
  elif grep -qi "is not installed\|downloadPlatform" "$LOG"; then echo "xcodebuild -downloadPlatform iOS"
  elif grep -q "requires a development team" "$LOG"; then echo "open BedtimeOrBust.xcodeproj, target BedtimeOrBust > Signing & Capabilities > Team (simulator builds normally need none)"
  else echo "paste the error lines above into the chat"
  fi
}
# run "what" command...: log everything, show the error lines on failure.
run() {
  local what=$1
  shift
  if ! "$@" >>"$LOG" 2>&1; then
    echo "--- error lines ---"
    grep -E "error:|error =|: fatal|failed|FAILED" "$LOG" | awk '!seen[$0]++' | tail -n 30 || true
    fail "$what" "$(hint)"
  fi
}

step "Xcode"
DEV=$(xcode-select -p 2>/dev/null || true)
case "$DEV" in
  *.app/Contents/Developer) ;;
  *) fail "xcode-select points to '${DEV:-nothing}', not Xcode" "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac
run "xcodebuild -version" xcodebuild -version
grep -E "^Xcode|^Build version" "$LOG" || true

step "iOS Simulator runtime"
run "listing simulator runtimes" xcrun simctl list runtimes
grep -E "^iOS" "$LOG" | tail -n 3 || fail "no iOS Simulator runtime installed" "xcodebuild -downloadPlatform iOS"

step "XcodeGen"
command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen is not installed" "brew install xcodegen   (no Homebrew? see https://brew.sh)"
xcodegen --version 2>&1 | tee -a "$LOG" || true

step "Engine tests (swift test)"
run "engine tests" swift test --package-path Core
grep -E "Executed [0-9]+ tests" "$LOG" | tail -n 1 || true

step "Generate BedtimeOrBust.xcodeproj"
run "xcodegen generate" xcodegen generate

step "Build the app for the iOS Simulator (first build takes a few minutes)"
run "app build" xcodebuild build \
  -project BedtimeOrBust.xcodeproj \
  -scheme BedtimeOrBust \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath "$DERIVED"
[ -d "$APP" ] || fail "the build said it succeeded but $APP is missing" "paste build/mac-build.log into the chat"
grep -c "warning:" "$LOG" | sed 's/^/warnings: /' || true
echo "BUILD SUCCEEDED: $APP"

[ "$LAUNCH" = 1 ] || exit 0

step "Launch in the Simulator"
# The newest runtime is listed last; take its last iPhone.
UDID=$(xcrun simctl list devices available | grep -E '^ +iPhone' | tail -n 1 | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)
[ -n "$UDID" ] || fail "no available iPhone simulator" "Xcode > Window > Devices and Simulators > Simulators > + (add an iPhone)"
xcrun simctl list devices available | grep "$UDID" | sed 's/^ */device: /'
xcrun simctl boot "$UDID" >>"$LOG" 2>&1 || true # fails harmlessly if already booted
open -a Simulator
run "waiting for the simulator to boot" xcrun simctl bootstatus "$UDID" -b
run "installing the app" xcrun simctl install "$UDID" "$APP"
run "launching the app" xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "Bedtime or Bust is running in the Simulator."
