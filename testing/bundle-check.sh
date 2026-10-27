#!/bin/bash
# Checks a built AgentValley.app before anyone gets it: both kinds of Mac, Sparkle inside and
# found, the signature whole, and the update keys only where they belong. A build for working on
# the app has no update keys, so it never replaces itself with a release. Prints each check that
# fails and exits 1 if any did.
#
#   testing/bundle-check.sh build/AgentValley.app dev       a build from ./build-app.sh
#   testing/bundle-check.sh build/release/AgentValley.app release   one release.sh made
# No pipes into grep -q: under pipefail, the writer dies of the early close and the check fails.
set -uo pipefail
APP="${1:?Name the app, e.g. testing/bundle-check.sh build/AgentValley.app dev}"
KIND="${2:?Say dev or release}"
BIN="$APP/Contents/MacOS/AgentValley"
PLIST="$APP/Contents/Info.plist"
fail=0
no() { echo "not ok: $*"; fail=1; }
key() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }

archs="$(lipo -archs "$BIN" 2>/dev/null)"
[[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || no "the program is for '$archs', not arm64 and x86_64"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || no "no Sparkle.framework in Contents/Frameworks"
grep -q '@executable_path/../Frameworks' <<<"$(otool -l "$BIN")" || no "the program does not look for frameworks in Contents/Frameworks"
codesign --verify --deep --strict "$APP" 2>/dev/null || no "the signature does not verify"
ents="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
grep -q 'com.apple.security.automation.apple-events' <<<"$ents" || no "the apple-events entitlement is missing"
details="$(codesign -dvv "$APP" 2>&1)"
grep -qE 'flags=0x[0-9a-f]+\([^)]*runtime' <<<"$details" || no "not signed with the hardened runtime"
[ -n "$(key CFBundleShortVersionString)" ] || no "no version"
[[ "$(key CFBundleVersion)" =~ ^[0-9]+$ ]] || no "build number is '$(key CFBundleVersion)', not a whole number Sparkle can compare"

case "$KIND" in
dev)
    [ -z "$(key SUFeedURL)" ] || no "a build for working on the app has SUFeedURL"
    grep -q 'com.apple.security.cs.disable-library-validation' <<<"$ents" || no "signed ad hoc without disable-library-validation, it cannot load Sparkle"
    ;;
release)
    [ "$(key SUFeedURL)" = "https://github.com/morsechimwai/agent-valley/releases/latest/download/appcast.xml" ] || no "SUFeedURL is '$(key SUFeedURL)'"
    [ -n "$(key SUPublicEDKey)" ] || no "no SUPublicEDKey"
    [ "$(key SUEnableAutomaticChecks)" = "true" ] || no "SUEnableAutomaticChecks is not true"
    [ "$(key SUScheduledCheckInterval)" = "3600" ] || no "SUScheduledCheckInterval is not 3600"
    [ "$(key SUEnableSystemProfiling)" = "false" ] || no "SUEnableSystemProfiling is not false"
    [ "$(key SUAutomaticallyUpdate)" = "false" ] || no "SUAutomaticallyUpdate is not false"
    grep -q 'Authority=Developer ID Application' <<<"$details" || no "not signed with a Developer ID"
    grep -q 'Timestamp=' <<<"$details" || no "the signature has no secure timestamp"
    ! grep -q 'disable-library-validation' <<<"$ents" || no "a release must not load code of another team"
    ;;
*)
    echo "Say dev or release, not $KIND"; exit 2
    ;;
esac
[ "$fail" = 0 ] && echo "ok: $APP ($KIND)"
exit "$fail"
