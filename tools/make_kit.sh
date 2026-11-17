#!/usr/bin/env bash
# Builds the launcher pack and the install kit players unzip once:
#   Overheat/Overheat.exe (stock Godot for Windows, renamed) + Overheat.pck (this launcher) + README.txt
# Godot loads Overheat.pck automatically because it sits next to Overheat.exe with the same name.
#   tools/make_kit.sh <godot-linux> <out dir> [godot version, default 4.7.2]
set -euo pipefail
G="$1"; OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; V="${3:-4.7.2}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
"$G" --headless --path "$SRC" --import >/dev/null 2>&1 || true
"$G" --headless --path "$SRC" --export-pack Launcher "$OUT/launcher.pck" >/dev/null 2>&1
test -s "$OUT/launcher.pck"
mkdir -p "$TMP/Overheat"
cp "$OUT/launcher.pck" "$TMP/Overheat/Overheat.pck"
curl -sSLo "$TMP/w.zip" "https://github.com/godotengine/godot-builds/releases/download/$V-stable/Godot_v$V-stable_win64.exe.zip"
unzip -q -o "$TMP/w.zip" -d "$TMP/w"
mv "$TMP"/w/Godot_v*_win64.exe "$TMP/Overheat/Overheat.exe"
cp "$SRC/tools/kit_readme.txt" "$TMP/Overheat/README.txt"
rm -f "$OUT/Overheat-Launcher.zip"
(cd "$TMP" && zip -q -r -9 "$OUT/Overheat-Launcher.zip" Overheat)
echo "kit: $OUT/Overheat-Launcher.zip, pack: $OUT/launcher.pck"
