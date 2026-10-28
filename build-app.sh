#!/bin/bash
# Builds AgentValley.app, a double-clickable bundle with no Dock icon, in build/ or in the
# folder named first (release.sh names its own). Signed ad hoc unless SIGN_IDENTITY names a
# certificate; with no SPARKLE_FEED it has no updates, so a build to work on never replaces
# itself with a release.
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-build}"

# Since the macOS 27 SDK, SwiftUI's @State is a macro, and the plugin that expands it comes with
# Xcode, not with the Command Line Tools. Without it, build against the newest older SDK at hand.
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if [ ! -e "$SDK/../../usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
    shopt -s nullglob
    # In name order, MacOSX26.sdk (the link to the newest 26) comes after MacOSX26.5.sdk.
    for older in "$SDK"/../MacOSX1[0-9]*.sdk "$SDK"/../MacOSX2[0-6]*.sdk; do export SDKROOT="$older"; done
    shopt -u nullglob
fi

# Both kinds of Mac in one program. That takes Xcode's build system; with the Command Line
# Tools alone, the build is for this Mac's kind only. The packages are public: SwiftPM has no
# reason to look in the Keychain, and once sat waiting on a prompt there.
if swift build -c release --disable-keychain --arch arm64 --arch x86_64; then
    BIN="$(swift build -c release --disable-keychain --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c release --disable-keychain
    BIN="$(swift build -c release --disable-keychain --show-bin-path)"
fi

APP="$DEST/AgentValley.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/AgentValley" "$APP/Contents/MacOS/AgentValley"
# Sparkle, where the program looks for it. Its XPC services are only for sandboxed apps, and
# this one is not, so they stay out: two fewer pieces to sign.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/AgentValley"

# The Claude Code plugin the person installs themselves, from the path the settings view shows.
mkdir -p "$APP/Contents/Resources"
cp -R plugin "$APP/Contents/Resources/claude-plugin"
# The icon Finder shows; testing/site.sh icon makes it from the website's crew mark.
cp AppIcon.icns "$APP/Contents/Resources/"
# The crew's faces for Claude Code's terminal; the user installs the font themselves.
cp AgentValleyCrew.ttf "$APP/Contents/Resources/"
# The boards the crew hangs up when a plan limit runs out; the app letters them.
cp signs/*.png "$APP/Contents/Resources/"
# The crew's voices: what each says when someone waits, when work is done, and on the way out and back.
cp -R sounds/crew "$APP/Contents/Resources/crew"
# Ours and Sparkle's licenses, which MIT asks to travel with every copy; Settings, About opens it.
{ cat LICENSE; printf '\n\n---\n\nSparkle (https://sparkle-project.org), bundled for updates:\n\n'; cat .build/artifacts/sparkle/Sparkle/LICENSE; } > "$APP/Contents/Resources/Licenses.txt"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>AgentValley</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.morsechimwai.agent-valley</string>
	<key>CFBundleName</key>
	<string>AgentValley</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.3.20</string>
	<key>CFBundleVersion</key>
	<string>39</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Shows the tab of the session you clicked, in your terminal.</string>
</dict>
</plist>
PLIST

# Only a release says where its updates are. Sparkle compares CFBundleVersion, so that goes up
# with every release; it asks before it installs, and sends nothing about the Mac.
if [ -n "${SPARKLE_FEED:-}" ]; then
    INFO="$APP/Contents/Info.plist"
    plutil -insert SUFeedURL -string "$SPARKLE_FEED" "$INFO"
    plutil -insert SUPublicEDKey -string "${SPARKLE_KEY:?SPARKLE_FEED needs SPARKLE_KEY, the public update key}" "$INFO"
    plutil -insert SUEnableAutomaticChecks -bool YES "$INFO"
    plutil -insert SUScheduledCheckInterval -integer 3600 "$INFO"
    plutil -insert SUEnableSystemProfiling -bool NO "$INFO"
    plutil -insert SUAutomaticallyUpdate -bool NO "$INFO"
fi

# The person can give this app leave to tell a terminal what to do, and it reads their Claude
# Code login when they turn Plan limits on. Signed with the hardened runtime, no other program
# can load code into its process and borrow either. That runtime in turn wants the request to
# tell another app what to do named here.
ENTITLEMENTS=".build/entitlements.plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
PLIST

# A Developer ID signature also carries Apple's timestamp, which notarization asks for. Sparkle's
# pieces are signed one by one, inside out, as Sparkle asks: --deep would hand the app's
# entitlements to all of them.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN=(codesign --force --options runtime --sign "$SIGN_IDENTITY")
[ "$SIGN_IDENTITY" = "-" ] || SIGN+=(--timestamp)
# The hardened runtime loads only code of the app's own team, and an ad hoc signature has none, so
# it would turn Sparkle away at launch. A release is one team throughout; only these builds let it in.
if [ "$SIGN_IDENTITY" = "-" ]; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS" >/dev/null
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
echo "Built $APP"
