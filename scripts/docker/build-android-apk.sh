#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ANDROID_HOME/platform-tools/adb" ]]; then
  echo "Android SDK is not initialized. Run: bash scripts/docker/prepare-android-sdk.sh" >&2
  exit 1
fi

if [[ ! -s "android/key.properties" ]]; then
  echo "WARNING: Android release APK will use the local debug key. Testing only; configure a dedicated persistent release key before distribution." >&2
fi

flutter pub get

if [[ -n "$POKOLENIE_API_BASE_URL" ]]; then
  if [[ ! "$POKOLENIE_API_BASE_URL" =~ ^https://[^[:space:]]+$ ]]; then
    echo "POKOLENIE_API_BASE_URL must be a public HTTPS URL without whitespace." >&2
    exit 1
  fi
  flutter build apk --release --target-platform android-arm64,android-x64 \
    --dart-define="POKOLENIE_API_BASE_URL=$POKOLENIE_API_BASE_URL"
else
  flutter build apk --release --target-platform android-arm64,android-x64
fi

APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -s "$APK" ]]; then
  echo "APK was not created: $APK" >&2
  exit 1
fi

echo
echo "APK: $APK"
sha256sum "$APK"
