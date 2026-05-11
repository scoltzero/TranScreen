#!/bin/bash
# Build, sign with Developer ID, notarize, staple, and package TranScreen as a DMG.
#
# Required environment:
#   TEAM_ID          — 10-character Apple Developer Team ID (e.g. ABCDE12345).
#                      Must match an installed "Developer ID Application" certificate.
#
# Optional environment:
#   NOTARY_PROFILE   — Keychain profile name created via `notarytool store-credentials`.
#                      Default: transcreen-notary.
#
# Local prerequisites (one-time):
#   1. Install a "Developer ID Application" certificate in your login keychain.
#   2. Generate an App-Specific Password at https://account.apple.com and run:
#        xcrun notarytool store-credentials transcreen-notary \
#            --apple-id <apple-id> --team-id <TEAM_ID>
#
# See docs/RELEASING.md for the full workflow.

set -euo pipefail

cd "$(dirname "$0")"

: "${TEAM_ID:?TEAM_ID is required (10-char Apple Developer Team ID)}"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-transcreen-notary}"

SCHEME="TranScreen"
CONFIGURATION="Release"
PROJECT="TranScreen.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/TranScreen.xcarchive"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/TranScreen.app"

step() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

step "Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

step "Generating ExportOptions.plist for team $TEAM_ID"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

step "Archiving (Release, signed with Developer ID + hardened runtime)"
# Force Developer ID + hardened runtime on the command line. Without these,
# CI runners with no provisioning profile silently fall back to ad-hoc
# "Sign to Run Locally" and notarization rejects the binary for missing
# the hardened runtime flag.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    archive

step "Exporting Developer ID signed app"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$BUILD_DIR/TranScreen-${VERSION}.dmg"

step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"

step "Creating DMG ($DMG_PATH)"
DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "TranScreen $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_PATH"

step "Submitting DMG for notarization (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

step "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

step "Validating final product"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true
xcrun stapler validate "$DMG_PATH"

printf "\n\033[1;32m✅ Done!\033[0m\n"
printf "App:  %s\n" "$APP_PATH"
printf "DMG:  %s\n" "$DMG_PATH"
printf "Version: %s (build %s)\n" "$VERSION" "$BUILD"
