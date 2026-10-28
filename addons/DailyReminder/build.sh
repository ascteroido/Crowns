#!/usr/bin/env bash
# Builds bin/DailyReminder.aar from android/: the reminder and the app icon
# switcher compiled against the Android SDK's android.jar, plus the manifest and
# resources (the notification icon, and the app icon variants that
# tools/make_icons.gd makes). No Gradle needed; the game's Gradle export dexes
# and merges the library into the APK.
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
# R.txt lists each resource once by type and name, whatever its folder's qualifiers.
find "$here/android/res" -type f | while read -r file; do
	folder="$(basename "$(dirname "$file")")"
	name="$(basename "$file")"
	echo "${folder%%-*} ${name%%.*}"
done | sort -u | awk '{
	if (!($1 in types)) types[$1] = length(types) + 1
	printf "int %s %s 0x7f%02x%04x\n", $1, $2, types[$1], count[$1]++
}' > "$work/aar/R.txt"

mkdir -p "$here/bin"
rm -f "$here/bin/DailyReminder.aar"
(cd "$work/aar" && zip -qrX "$here/bin/DailyReminder.aar" .)
echo "Built $here/bin/DailyReminder.aar"
