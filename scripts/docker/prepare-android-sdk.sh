#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME is not set. Start this script inside the Pokolenie dev container." >&2
  exit 1
fi

echo "Android SDK licenses will be shown for interactive acceptance."
echo "Read the license prompts and accept only if you agree."
flutter doctor --android-licenses

sdkmanager --sdk_root="$ANDROID_HOME" --install \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "ndk;28.2.13676358"

flutter doctor -v
