#!/usr/bin/env bash
# The headless gates from docs/rules.md §6: import, then each screen. Run from the project root:
#   GODOT=/path/to/Godot_v4.7.2 tests/gates.sh
# Exits 1 when any run prints an error that is not listed as expected noise (docs/skills.md).
set -u
GODOT=${GODOT:?set GODOT to the Godot 4.7.2 binary}
NOISE='ObjectDB instances leaked at exit|resources still in use at exit'
# splash, loading, session_list and world_intro are left out: headless they fail their threaded loads
# (issue #22). Windowed they are clean.
SCENES=(
  "res://scenes/ui/boot/peek.tscn 30"
  "res://scenes/battle/battle.tscn 20"
  "res://scenes/overworld/region_map.tscn 30"
  "res://scenes/review_session/categorizer.tscn 20"
  "res://scenes/review_session/flashcards.tscn 20"
  "res://scenes/ui/settings.tscn 20"
)
failed=0

gate() {
  local label=$1; shift
  local out bad
  out=$(timeout 300 "$GODOT" --headless --path . "$@" 2>&1)
  bad=$(printf '%s\n' "$out" | grep -E 'ERROR|Parse Error' | grep -vE "$NOISE")
  if [ -n "$bad" ]; then
    echo "FAIL $label"
    printf '%s\n' "$bad"
    failed=1
  else
    echo "ok   $label"
  fi
}

# A fresh clone (CI) needs two passes before an import is clean: the first builds the script class
# cache and stops, the second imports the assets while the theme is still missing. Neither is a gate.
if [ ! -d .godot/imported ]; then
  for _ in 1 2; do timeout 600 "$GODOT" --headless --path . --import > /dev/null 2>&1; done
fi
gate import --import
for spec in "${SCENES[@]}"; do
  read -r scene frames <<< "$spec"
  gate "$scene" "$scene" --quit-after "$frames"
done
exit $failed
