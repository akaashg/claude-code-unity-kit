#!/bin/sh
# unity-kit reference check: every GUID that a scene, prefab or other text asset references belongs to a .meta.
# Usage: ref-check.sh [--state dir] [project_dir]
#   --state dir   cache the GUIDs found in Library/PackageCache in dir, keyed on the package folders
#
# Unity stores a reference to another asset as {fileID: ..., guid: <32 hex>, type: ...}, and an asmdef
# references another asmdef as "GUID:<32 hex>". When no .meta has that GUID, Unity shows the reference
# as Missing, and the scene or prefab drops it on the next save.
#
# A broken reference is new, and blocks, when either
#   - its GUID was in a .meta at HEAD (the asset was deleted, or moved without its .meta, since the last commit), or
#   - the referencing file changed since HEAD and no asset or package has the GUID (written by hand).
# Broken references already in the last commit are counted but do not block.
#
# Exit: 0 no new broken references, 1 new broken references,
#       2 could not tell (no git, or no Library/PackageCache to resolve a changed file), 3 not a Unity project.
# Only text (Force Text) assets are scanned; binary-serialized assets are skipped.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

STATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state) STATE=$2; shift ;;
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

TMP=${TMPDIR:-/tmp}/unity-kit-ref.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
cd "$PROJECT" || exit 3

dirs="Assets"
[ -d Packages ] && dirs="$dirs Packages"

# Text assets and asmdefs that reference other assets by GUID.
EXTS="unity prefab asset mat anim controller overrideController mask playable signal mixer physicMaterial
  physicsMaterial2D renderTexture cubemap flare guiskin fontsettings spriteatlas spriteatlasv2 lighting
  terrainlayer brush preset shadervariants giparams asmdef asmref"

HAVE_GIT=0
command -v git >/dev/null 2>&1 && git rev-parse --verify -q HEAD >/dev/null 2>&1 && HAVE_GIT=1
# In a git repo, read Assets/ and Packages/ with git grep (tracked, untracked and ignored files alike):
# one multithreaded process, several times faster than find + grep on Windows. git grep does not
# enter submodules or nested repositories, so fall back to find when there are any.
FAST=0
if [ "$HAVE_GIT" -eq 1 ] && ! git ls-files --stage -- $dirs 2>/dev/null | grep -q '^160000' &&
  [ -z "$(find $dirs -name .git -print 2>/dev/null | head -n 1)" ]; then
  FAST=1
fi
SEP=$(printf '\001')
# awk filter for git grep -z lines ("path<SEP>line<SEP>match"): drop what Unity does not import (same
# rules as meta-check.sh). The answer is cached per path: a scene has thousands of lines.
IMPORTED='!($1 in ok) { ok[$1] = 1; n = split($1, part, "/"); for (i = 1; i <= n; i++) { q = tolower(part[i]); if (q ~ /^\./ || q ~ /~$/ || q == "cvs" || q ~ /\.tmp$/) ok[$1] = 0 } } !ok[$1] { next }'
git_grep() { # pattern pathspec...
  pattern=$1; shift
  git -c core.quotepath=off grep --untracked --no-exclude-standard --no-color -z -I -n -o -E "$pattern" -- "$@" 2>/dev/null |
    tr -d '\r' | tr '\000' "$SEP"
}

# GUIDs of the .meta files under the given folders, one per line.
meta_guids() {
  find "$@" -mindepth 1 \( -name '.*' -o -name '*~' -o -iname 'cvs' -o -name '*.tmp' \) -prune -o \
    -type f -name '*.meta' -exec grep -h '^guid: ' {} + 2>/dev/null |
    tr -d '\r' | sed -E -n 's/^guid: ([0-9a-f]{32}).*/\1/p'
}
project_meta_guids() {
  if [ "$FAST" -eq 0 ]; then meta_guids $dirs; return; fi
  set -f
  specs=""; for d in $dirs; do specs="$specs :(glob)$d/**/*.meta"; done
  git_grep '^guid: [0-9a-f]{32}' $specs | awk -F "$SEP" "$IMPORTED"' { print substr($3, 7, 32) }'
  set +f
}

# Every GUID referenced from a text asset or asmdef, as "guid line file".
references() {
  set -f
  if [ "$FAST" -eq 1 ]; then
    specs=""; for d in $dirs; do for e in $EXTS; do specs="$specs :(glob)$d/**/*.$e"; done; done
    git_grep '(guid: |GUID:)[0-9a-f]{32}' $specs |
      awk -F "$SEP" "$IMPORTED"' { print substr($3, length($3) - 31), $2, $1 }'
  else
    names=""; for e in $EXTS; do names="$names -o -name *.$e"; done
    find $dirs -mindepth 1 \( -name '.*' -o -name '*~' -o -iname 'cvs' -o -name '*.tmp' \) -prune -o -type f \
      \( ${names# -o } \) -exec grep -H -I -n -o -E '(guid: |GUID:)[0-9a-f]{32}' {} + 2>/dev/null |
      sed -E -n 's/^(.*):([0-9]+):(guid: |GUID:)([0-9a-f]{32})$/\4 \2 \1/p'
  fi
  set +f
}

# Known GUIDs: the project's assets and embedded packages, local packages outside the project
# (file: in manifest.json), and downloaded packages in Library/PackageCache.
project_meta_guids > "$TMP/known"
if [ -f Packages/manifest.json ]; then
  tr -d '\r' < Packages/manifest.json | grep -o '"file:[^"]*"' | sed 's/^"file://; s/"$//; s#\\\\#/#g' |
    while IFS= read -r p; do
      case "$p" in /*|[A-Za-z]:*) ;; *) p="Packages/$p" ;; esac
      [ -d "$p" ] && meta_guids "$p"
    done >> "$TMP/known"
fi
HAVE_PC=0
if [ -d Library/PackageCache ]; then
  HAVE_PC=1
  # Package folder names carry a version or hash, so the listing changes whenever a package does.
  stamp=$(ls -1 Library/PackageCache 2>/dev/null | cksum)
  cache=""
  if [ -n "$STATE" ]; then
    STATE=$(printf '%s' "$STATE" | sed 's#\\#/#g')
    mkdir -p "$STATE" 2>/dev/null
    cache="$STATE/$(printf '%s' "$PROJECT" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-').pkg-guids"
  fi
  if [ -n "$cache" ] && [ -f "$cache" ] && [ "$(head -n 1 "$cache")" = "$stamp" ]; then
    sed 1d "$cache" >> "$TMP/known"
  elif [ "$FAST" -eq 1 ]; then
    # Library/ is ignored but inside the worktree, so git grep reads it too. A package folder it
    # returns nothing for (a nested repository) is read with find instead.
    git_grep '^guid: [0-9a-f]{32}' ':(glob)Library/PackageCache/**/*.meta' |
      awk -F "$SEP" "$IMPORTED"' { split($1, part, "/"); print part[3], substr($3, 7, 32) }' > "$TMP/pkgrows"
    cut -d' ' -f2 "$TMP/pkgrows" > "$TMP/pkg"
    cut -d' ' -f1 "$TMP/pkgrows" | sort -u > "$TMP/pkgseen"
    ls -1 Library/PackageCache 2>/dev/null | sort | comm -23 - "$TMP/pkgseen" | while IFS= read -r f; do
      [ -d "Library/PackageCache/$f" ] && meta_guids "Library/PackageCache/$f"
    done >> "$TMP/pkg"
    cat "$TMP/pkg" >> "$TMP/known"
    [ -n "$cache" ] && { echo "$stamp"; cat "$TMP/pkg"; } > "$cache" 2>/dev/null
  else
    meta_guids Library/PackageCache > "$TMP/pkg"
    cat "$TMP/pkg" >> "$TMP/known"
    [ -n "$cache" ] && { echo "$stamp"; cat "$TMP/pkg"; } > "$cache" 2>/dev/null
  fi
fi
sort -u "$TMP/known" -o "$TMP/known"

# Unresolved references, one row per GUID and file: "guid first-line count file".
# GUIDs starting with 16 zeros are Unity's built-in resources (default resources, builtin extra).
references | awk '
  FILENAME == ARGV[1] { known[$1] = 1; next }
  $1 ~ /^0000000000000000/ || ($1 in known) { next }
  {
    file = substr($0, length($1) + length($2) + 3); key = $1 " " file
    if (!(key in first)) { first[key] = $2; order[++n] = key }
    else if ($2 + 0 < first[key] + 0) first[key] = $2
    count[key]++
  }
  END { for (i = 1; i <= n; i++) { k = order[i]; split(k, g, " "); print g[1], first[k], count[k], substr(k, 34) } }
' "$TMP/known" - > "$TMP/broken"

serialization=$(sed -n 's/^ *m_SerializationMode: *//p' ProjectSettings/EditorSettings.asset 2>/dev/null | tr -d '\r')
note_binary() {
  [ -n "$serialization" ] && [ "$serialization" != "2" ] &&
    echo "unity-kit: Asset Serialization is not Force Text, so binary scenes and prefabs were not checked."
  return 0
}

if [ ! -s "$TMP/broken" ]; then
  echo "unity-kit: every asset reference resolves to a .meta."
  note_binary
  exit 0
fi

# Which broken references are new since HEAD: GUIDs of .meta files deleted or changed since HEAD
# (with the asset's old path), and files changed or added since HEAD.
: > "$TMP/head"; : > "$TMP/changed"; : > "$TMP/before"
if [ "$HAVE_GIT" -eq 1 ]; then
  set -f
  specs=""; for d in $dirs; do specs="$specs :(glob)$d/**/*.meta"; done
  git -c core.quotepath=off diff --no-renames --diff-filter=DM --relative --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ HEAD -- $specs 2>/dev/null | tr -d '\r' | awk '
      /^--- a\// { p = substr($0, 7); sub(/\t$/, "", p); sub(/\.meta$/, "", p); next }
      /^-guid: [0-9a-f]/ { print substr($0, 8, 32), p }' > "$TMP/head"
  set +f
  { git -c core.quotepath=off diff --name-only --relative HEAD -- $dirs
    git -c core.quotepath=off ls-files --others --exclude-standard -- $dirs; } 2>/dev/null > "$TMP/changed"
  # GUIDs that changed files with broken references already referenced at HEAD, as "guid file":
  # an unrelated edit to a file must not make its old broken references count as new.
  awk 'FILENAME == ARGV[1] { c[$0] = 1; next } { f = substr($0, length($1) + length($2) + length($3) + 4); if (f in c && !(f in seen)) { seen[f] = 1; print f } }' \
    "$TMP/changed" "$TMP/broken" |
    while IFS= read -r f; do
      git show "HEAD:./$f" 2>/dev/null | grep -o -E '(guid: |GUID:)[0-9a-f]{32}' | sed -E 's/^(guid: |GUID:)//' |
        awk -v f="$f" '{ print $0, f }'
    done > "$TMP/before"
fi

# Sort each row into new (N), could not tell (U) or already in the last commit (P).
# An unknown GUID in an asmdef never blocks by itself: Asset Store asmdefs reference optional
# assemblies that are often not installed, and the compile check catches the ones that matter.
awk -v git="$HAVE_GIT" -v pc="$HAVE_PC" '
  FILENAME == ARGV[1] { was[$1] = substr($0, 34); next }
  FILENAME == ARGV[2] { changed[$0] = 1; next }
  FILENAME == ARGV[3] { before[$0] = 1; next }
  {
    g = $1; file = substr($0, length($1) + length($2) + length($3) + 4)
    where = file " line " $2 (($3 > 1) ? " (" $3 " references)" : "") ": guid " g
    added = (file in changed) && !((g " " file) in before) && file !~ /\.asm(def|ref)$/
    if (g in was)              print "N  " where ", was " was[g] " at HEAD"
    else if (!git)             print "U  " where
    else if (added && pc)      print "N  " where ", no asset or package has this GUID"
    else if (added)            print "U  " where
    else                       print "P  " where
  }
' "$TMP/head" "$TMP/changed" "$TMP/before" "$TMP/broken" > "$TMP/sorted"

section() { # tag
  grep "^$1  " "$TMP/sorted" | sed 's/^.  /  /' | head -n 50
}
status=0
if grep -q '^N  ' "$TMP/sorted"; then
  echo "unity-kit: broken asset references since the last commit (Unity shows them as Missing):"
  section N
  echo "  Do not invent or copy GUIDs. Restore the deleted asset with its .meta (git checkout HEAD -- <asset> <asset>.meta),"
  echo "  move the .meta along with a moved asset, or tell the user to reassign the reference in the Editor."
  status=1
fi
if grep -q '^U  ' "$TMP/sorted"; then
  if [ "$HAVE_GIT" -eq 0 ]; then
    echo "unity-kit: references to GUIDs no .meta has (no git history to tell new ones from old ones):"
  else
    echo "unity-kit: changed files reference GUIDs not found in the project, and Library/PackageCache is missing, so they may be package assets (open the project in Unity once to check):"
  fi
  section U
  [ "$status" -eq 0 ] && status=2
fi
pre=$(grep -c '^P  ' "$TMP/sorted")
if [ "$pre" -gt 0 ]; then
  if [ "$HAVE_PC" -eq 1 ]; then
    echo "unity-kit: $pre broken reference(s) already in the last commit (not new; not blocking):"
    section P | head -n 20
  else
    echo "unity-kit: $pre reference(s) from unchanged files could not be resolved; Library/PackageCache is missing, so most are probably package assets."
  fi
fi
[ "$status" -eq 0 ] && echo "unity-kit: no new broken asset references."
note_binary
exit $status
