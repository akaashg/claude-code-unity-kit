#!/bin/sh
# unity-kit .meta check: every asset under Assets/ has a .meta, and every .meta has its asset.
# Usage: meta-check.sh [project_dir]
# Exit: 0 all paired, 1 orphaned .meta files (an asset was moved or deleted without its .meta),
#       2 only assets without .meta (new files Unity has not imported yet, or a move that left the .meta behind),
#       3 not a Unity project.
# Follows Unity's import rules: names starting with "." or ending with "~", "cvs" and "*.tmp" are ignored.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

PROJECT=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
PROJECT=$(printf '%s' "$PROJECT" | sed 's#\\#/#g; s#/$##')
if [ ! -d "$PROJECT/Assets" ] || [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
  echo "unity-kit: $PROJECT is not a Unity project root."
  exit 3
fi

TMP=${TMPDIR:-/tmp}/unity-kit-meta.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

cd "$PROJECT" || exit 3
find Assets -mindepth 1 \( -name '.*' -o -name '*~' -o -iname 'cvs' -o -name '*.tmp' \) -prune -o -print |
  tr -d '\r' > "$TMP/all"
grep -v '\.meta$' "$TMP/all" | LC_ALL=C sort > "$TMP/assets"
grep '\.meta$' "$TMP/all" | sed 's/\.meta$//' | LC_ALL=C sort > "$TMP/metas"

LC_ALL=C comm -13 "$TMP/assets" "$TMP/metas" > "$TMP/orphans"
LC_ALL=C comm -23 "$TMP/assets" "$TMP/metas" > "$TMP/missing"

status=0
if [ -s "$TMP/orphans" ]; then
  echo "unity-kit: .meta files with no asset (asset moved or deleted without its .meta; references to it are now broken):"
  sed 's/^/  /; s/$/.meta/' "$TMP/orphans" | head -n 50
  status=1
fi
if [ -s "$TMP/missing" ]; then
  echo "unity-kit: assets with no .meta (new and not yet imported by Unity, or moved without their .meta):"
  sed 's/^/  /' "$TMP/missing" | head -n 50
  echo "  Do not write .meta files by hand. If an asset was moved, move its old .meta with it; otherwise let Unity import it."
  [ "$status" -eq 0 ] && status=2
fi
[ "$status" -eq 0 ] && echo "unity-kit: every asset under Assets/ has its .meta."
exit $status
