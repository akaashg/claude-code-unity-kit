#!/bin/sh
# Checks that every skill and agent file has YAML frontmatter with name and description.
# Usage: sh tests/frontmatter.test.sh
cd "$(dirname "$0")/.." || exit 1
fails=0
for f in plugins/*/skills/*/SKILL.md plugins/*/agents/*.md; do
  [ -f "$f" ] || continue
  head -n 1 "$f" | tr -d '\r' | grep -qx -- '---' || { echo "FAIL $f: first line is not ---"; fails=$((fails + 1)); continue; }
  fm=$(awk 'NR == 1 { next } /^---\r?$/ { exit } { print }' "$f")
  for key in name description; do
    printf '%s\n' "$fm" | grep -q "^$key:" || { echo "FAIL $f: no $key"; fails=$((fails + 1)); }
  done
  len=$(printf '%s\n' "$fm" | sed -n 's/^description: *//p' | wc -c)
  [ "$len" -le 1536 ] || { echo "FAIL $f: description over 1536 chars"; fails=$((fails + 1)); }
  echo "ok   $f"
done
[ "$fails" -eq 0 ]
