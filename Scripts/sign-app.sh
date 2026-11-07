#!/bin/bash
# Signs Sparkle's bundled helpers and then the app, so the result can be notarized.
# Xcode's build step signs the Sparkle framework but leaves the helpers inside it as shipped.
#
# Usage: Scripts/sign-app.sh "path/to/VPN Bar.app" "Developer ID Application"
set -euo pipefail

app="$1"
identity="$2"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() {
  codesign --force --options runtime --timestamp --sign "$identity" "$@"
}

sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --preserve-metadata=entitlements "$app"

codesign --verify --deep --strict "$app"
