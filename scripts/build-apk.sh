#!/usr/bin/env bash
#
# Builds a universal, release-signed Fathom APK for a GitHub release upload,
# named for the pubspec version (no ABI marker, so the in-app updater treats it
# as the universal build). The versionCode is epoch seconds — always increasing,
# so the OS installer never rejects the update as a downgrade, with no counter
# to track by hand. The version NAME comes from pubspec.yaml, so bump that to the
# release version (e.g. 0.11.0-dev03) before running.
#
# Requires android/key.properties + the Fathom keystore (release signing).
#
# Usage:  scripts/build-apk.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release --build-number "$(date +%s)"

ver=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//; s/+.*//')
src="build/app/outputs/flutter-apk/app-release.apk"
out="build/app/outputs/flutter-apk/Fathom-${ver}.apk"
cp "$src" "$out"

echo ""
echo "Built universal release APK:"
echo "  $out"
echo "Upload this to the GitHub release for v${ver}."
