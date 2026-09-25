#!/usr/bin/env bash
# Builds the signed release APK.
# Needs: Godot 4.7.2 + export templates, Android SDK build-tools, JDK 17+,
# and the release keystore (kept outside the repo).
#   GODOT=/path/to/godot KEYSTORE=/path/meltiew-release.keystore KEYSTORE_PASS=... ./build_android.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${GODOT:=godot}"
: "${KEYSTORE:?set KEYSTORE to the release keystore path}"
: "${KEYSTORE_PASS:?set KEYSTORE_PASS}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KEYSTORE_ALIAS:-meltiew}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEYSTORE_PASS"
mkdir -p export
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Android" export/meltiew.apk
echo "Built export/meltiew.apk"
