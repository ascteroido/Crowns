#!/usr/bin/env bash
# Fetches the puzzle packs tools/make_packs.gd is building on another machine,
# checks the new puzzles in them (tools/check_packs.gd) and adds the sound ones
# to puzzles/:
#   tools/sync_packs.sh user@host [remote_dir]
# remote_dir defaults to /tmp/crowns-build/crowns. Once make_packs.gd is no
# longer running there, it syncs one last time and turns off the
# crowns-pack-sync timer that runs it every 10 minutes, if there is one.
set -uo pipefail

host="$1"
remote="${2:-/tmp/crowns-build/crowns}"
here="$(cd "$(dirname "$0")/.." && pwd)"
staging="${XDG_CACHE_HOME:-$HOME/.cache}/crowns-pack-sync"
godot="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"

running="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$host" "pgrep -f 'make_pack[s].gd' >/dev/null && echo yes || echo no")" || {
	echo "Couldn't reach $host"
	exit 1
}
rm -rf "$staging"
mkdir -p "$staging"
scp -q -o BatchMode=yes "$host:$remote/puzzles/*.pack" "$staging/" || {
	echo "No packs to fetch from $host:$remote/puzzles"
	exit 1
}
"$godot" --headless --path "$here" --script res://tools/check_packs.gd -- "$staging" 2>&1 | grep -v "^Godot Engine"
status=${PIPESTATUS[0]}

if [ "$running" = no ]; then
	echo "make_packs.gd isn't running on $host any more; that was the last sync."
	systemctl --user disable --now crowns-pack-sync.timer 2>/dev/null || true
fi
exit "$status"
