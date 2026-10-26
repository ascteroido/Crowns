#!/usr/bin/env bash
# Builds bin/DailyReminder.aar from android/: the receiver compiled against the
# Android SDK's android.jar, plus its manifest and icon. No Gradle needed; the
# game's Gradle export dexes and merges the library into the APK.
#   addons/DailyReminder/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
android_jar="$(ls -d "$sdk"/platforms/android-*/android.jar | sort -V | tail -n 1)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/classes" "$work/aar"
javac --release 11 -classpath "$android_jar" -d "$work/classes" \
	$(find "$here/android/src" -name '*.java')
(cd "$work/classes" && jar cf "$work/aar/classes.jar" .)
cp "$here/android/AndroidManifest.xml" "$work/aar/"
cp -r "$here/android/res" "$work/aar/"
echo "int drawable crowns_reminder_icon 0x7f010000" > "$work/aar/R.txt"

mkdir -p "$here/bin"
rm -f "$here/bin/DailyReminder.aar"
(cd "$work/aar" && zip -qrX "$here/bin/DailyReminder.aar" .)
echo "Built $here/bin/DailyReminder.aar"
