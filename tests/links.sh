#!/usr/bin/env bash
# Every relative Markdown link in the tracked docs points at a file that exists (docs/rules.md §6).
# Run from the project root: tests/links.sh. Prints each broken link; exits 1 if there is one.
missing=0
while IFS= read -r f; do
  # Deleted but not yet committed: git still lists it.
  [ -f "$f" ] || continue
  dir=$(dirname "$f")
  while IFS= read -r link; do
    target=${link%%#*}
    case $target in ''|http:*|https:*|mailto:*) continue ;; esac
    [ -e "$dir/$target" ] || { echo "$f: missing $target"; missing=1; }
  done < <(grep -oE '\]\([^) ]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
done < <(git ls-files '*.md' | grep -vE '^addons/')
exit $missing
