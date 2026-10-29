#!/bin/sh
# unity-kit repository and project integrity check, through Unity's own CLI.
# Usage: unity-verify.sh [--base ref] [project_dir]
#   --base ref   count files changed since ref (for example origin/main in CI) as touched by this change,
#                besides uncommitted changes. Default: only changes since HEAD.
#
# Runs, both read-only (this script never passes --fix):
#   unity projects verify   missing or orphaned .meta files, duplicate GUIDs, conflict markers,
#                           an invalid Packages/manifest.json
#   unity vcs doctor        git settings, ignore rules, LFS patterns and package pinning (git repos only)
# These complement ref-check.sh: they check the repository and the .meta files, not the references
# inside scenes and prefabs.
#
# An error blocks only when its file is one this change touched, the same rule ref-check.sh uses,
# so problems already in the repository are listed without blocking every commit. Without git,
# every error blocks.
#
# Exit: 0 no blocking errors (warnings and older problems are listed), 1 errors in touched files,
#       3 not checked (a command failed to run, or not a Unity project), 4 the Unity CLI isn't installed.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE=$2; shift ;;
    *) break ;;
  esac
  shift
done
PROJECT=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
PROJECT=$(printf '%s' "$PROJECT" | sed 's#\\#/#g; s#/$##')
if [ ! -d "$PROJECT/Assets" ] || [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
  echo "unity-kit: $PROJECT is not a Unity project root."
  exit 3
fi

UNITY_CLI=${UNITY_KIT_UNITY_CLI:-unity}   # tests point this at a fake, or at "none"
if [ "$UNITY_CLI" = none ] || ! command -v "$UNITY_CLI" >/dev/null 2>&1; then
  echo "unity-kit: the Unity CLI isn't installed, so Unity's integrity checks were skipped (not installed)."
  exit 4
fi

TMP=${TMPDIR:-/tmp}/unity-kit-verify.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
cd "$PROJECT" || exit 3
export UNITY_NO_BANNER=1 UNITY_NON_INTERACTIVE=1 UNITY_NO_PAGER=1 NO_COLOR=1

# Files this change touched, relative to the project.
HAVE_GIT=0
: > "$TMP/changed"
if command -v git >/dev/null 2>&1 && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  HAVE_GIT=1
  { git -c core.quotepath=off diff --name-only --relative HEAD
    [ -n "$BASE" ] && git -c core.quotepath=off diff --name-only --relative "$BASE...HEAD"
    git -c core.quotepath=off ls-files --others --exclude-standard; } 2>/dev/null | sort -u > "$TMP/changed"
fi

# One line per finding: "severity<TAB>source<TAB>code<TAB>where<TAB>message<TAB>fixable".
: > "$TMP/findings"
notes=""
not_checked=""

"$UNITY_CLI" projects verify . --format tsv > "$TMP/verify" 2> "$TMP/verify.err"
rc=$?
if [ "$rc" -eq 0 ] || { [ "$rc" -eq 6 ] && [ -s "$TMP/verify" ]; }; then
  # projects verify: code, severity, path, line, message
  tr -d '\r' < "$TMP/verify" | awk -F '\t' 'NF >= 5 {
    where = $3; if ($4 != "" && $4 != "0") where = where ":" $4
    print $2 "\tverify\t" $1 "\t" where "\t" $5 "\tfalse" }' >> "$TMP/findings"
else
  not_checked="unity projects verify didn't run (exit $rc): $(tr -d '\r' < "$TMP/verify.err" | grep -v '^[[:space:]]*$' | head -n 1)"
fi

if [ "$HAVE_GIT" -eq 1 ]; then
  "$UNITY_CLI" vcs doctor --format tsv > "$TMP/doctor" 2> "$TMP/doctor.err"
  rc=$?
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 4 ]; then
    # vcs doctor: code, severity, path, fixable, message
    tr -d '\r' < "$TMP/doctor" | awk -F '\t' 'NF >= 5 {
      print $2 "\tdoctor\t" $1 "\t" $3 "\t" $5 "\t" $4 }' >> "$TMP/findings"
  else
    msg="unity vcs doctor didn't run (exit $rc): $(tr -d '\r' < "$TMP/doctor.err" | grep -v '^[[:space:]]*$' | head -n 1)"
    not_checked="${not_checked:+$not_checked
}$msg"
  fi
else
  notes="unity vcs doctor skipped: the project isn't in a git repository with a commit."
fi

# Sort into blocking (B), already in the repository (E), warning (W) and notice (N).
awk -F '\t' -v git="$HAVE_GIT" '
  FILENAME == ARGV[1] { changed[$0] = 1; next }
  {
    path = $4; sub(/:[0-9]+$/, "", path)
    line = "  " $3 " " $4 ": " $5 (($6 == "true") ? " (fixable: unity vcs doctor --fix)" : "")
    if ($1 == "error") print ((!git || (path in changed)) ? "B" : "E") line
    else if ($1 == "warning") print "W" line
    else print "N" line
  }
' "$TMP/changed" "$TMP/findings" > "$TMP/sorted"

section() { grep "^$1" "$TMP/sorted" | cut -c2- | head -n "${2:-50}"; }
count() { grep -c "^$1" "$TMP/sorted"; }

status=0
if [ "$(count B)" -gt 0 ]; then
  echo "unity-kit: Unity integrity errors in files this change touched:"
  section B
  status=1
fi
if [ "$(count E)" -gt 0 ]; then
  echo "unity-kit: $(count E) Unity integrity error(s) already in the repository (not in files this change touched; not blocking):"
  section E 20
fi
if [ "$(count W)" -gt 0 ]; then
  echo "unity-kit: $(count W) warning(s):"
  section W 20
fi
[ "$(count N)" -gt 0 ] && echo "unity-kit: $(count N) notice(s) left out; run unity vcs doctor to see them."
[ -n "$notes" ] && echo "unity-kit: $notes"
if [ -n "$not_checked" ]; then
  printf 'unity-kit: %s\n' "$not_checked"
  [ "$status" -eq 0 ] && status=3
fi
case $status in
  0) echo "unity-kit: no Unity integrity errors in files this change touched." ;;
  1) echo "unity-kit: fix these, or tell the user which ones need the Editor. Never run --fix without asking." ;;
  3) echo "unity-kit: Unity's integrity checks were not fully checked." ;;
esac
exit $status
