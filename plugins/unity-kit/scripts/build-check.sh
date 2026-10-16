#!/bin/sh
# unity-kit player build check.
# Usage: build-check.sh --target T [--profile P] [--method Class.Method] [--output path] [--state dir] [project_dir]
#   --target T     BuildTarget name: StandaloneWindows64, StandaloneOSX, StandaloneLinux64, Android, iOS, WebGL, ...
#   --profile P    Unity 6 build profile: an .asset path relative to the project, or a name in Assets/Settings/Build Profiles
#   --method M     static Editor method that builds the player (it gets -buildOutput <path>)
#   --output path  where the player goes (default: Builds/unity-kit/<target>/ in the project)
#   --state dir    remember the build size per target in dir, and print the change from the last build
#
# Before building, checks the scene list in ProjectSettings/EditorBuildSettings.asset.
# Routes, first one that works wins. Both launch Unity in batch mode, so neither can run
# while the Editor has the project open:
#   1. Unity CLI `unity build`
#   2. Batch mode: -build<Platform>Player for desktop targets, -activeBuildProfile + -build for a
#      build profile, -executeMethod for everything else
# Other targets without a profile need an -executeMethod script; Assets/Editor/UnityKitBuild.cs is
# used when it exists (the build-fix skill offers to add it).
#
# Exit: 0 build succeeded, 1 build errors, 3 not checked (Editor open, no Unity, no build method, not a Unity project).
# Output: a short report for Claude. Errors are printed as "File(line,col): error CLASS: ..." where the
# log names a file, else "error CLASS: ...". Patterns live in build-patterns.txt next to this script.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

TARGET=""; PROFILE=""; METHOD=""; OUTPUT=""; STATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET=$2; shift ;;
    --profile) PROFILE=$2; shift ;;
    --method) METHOD=$2; shift ;;
    --output) OUTPUT=$2; shift ;;
    --state) STATE=$2; shift ;;
    *) break ;;
  esac
  shift
done
PROJECT=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
PROJECT=$(printf '%s' "$PROJECT" | sed 's#\\#/#g; s#/$##')
# Git Bash: /e/Game -> E:/Game, the form Unity writes in its logs.
command -v cygpath >/dev/null 2>&1 && PROJECT=$(cygpath -m "$PROJECT")
PATTERNS="$(dirname "$0")/build-patterns.txt"
UNITY_CLI=${UNITY_KIT_UNITY_CLI:-unity}   # tests point this at a fake, or at "none"
HELPER_METHOD=UnityKit.UnityKitBuild.Build

if [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
  echo "unity-kit: $PROJECT is not a Unity project root (no ProjectSettings/ProjectVersion.txt)."
  exit 3
fi
if [ -z "$TARGET" ] && [ -z "$PROFILE" ]; then
  echo "unity-kit: no build target. Pass --target (StandaloneWindows64, StandaloneOSX, StandaloneLinux64, Android, iOS, WebGL, ...) or --profile. Not checked."
  exit 3
fi

NAME=$(basename "$PROJECT")
VERSION=$(sed -n 's/^m_EditorVersion: *//p' "$PROJECT/ProjectSettings/ProjectVersion.txt" | tr -d '\r')
TMP=${TMPDIR:-/tmp}/unity-kit-build.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# ---- Build profile ------------------------------------------------------------
PROFILE_REL=""
if [ -n "$PROFILE" ]; then
  case "$PROFILE" in
    *.asset) PROFILE_REL=$PROFILE ;;
    *) PROFILE_REL="Assets/Settings/Build Profiles/$PROFILE.asset" ;;
  esac
  PROFILE_REL=${PROFILE_REL#"$PROJECT"/}
  if [ ! -f "$PROJECT/$PROFILE_REL" ]; then
    echo "unity-kit: build profile $PROFILE_REL not found. Profiles in this project:"
    find "$PROJECT/Assets" -path '*Build Profiles*' -name '*.asset' 2>/dev/null | sed "s#^$PROJECT/#  #"
    echo "unity-kit: not checked."
    exit 3
  fi
  if [ -z "$TARGET" ]; then
    # m_BuildTarget holds the BuildTarget enum value.
    case $(sed -n 's/^ *m_BuildTarget: *//p' "$PROJECT/$PROFILE_REL" | tr -d '\r' | head -n 1) in
      2) TARGET=StandaloneOSX ;; 5) TARGET=StandaloneWindows ;; 9) TARGET=iOS ;; 13) TARGET=Android ;;
      19) TARGET=StandaloneWindows64 ;; 20) TARGET=WebGL ;; 21) TARGET=WSAPlayer ;; 24) TARGET=StandaloneLinux64 ;;
      *) TARGET=$(basename "$PROFILE_REL" .asset | tr -c 'A-Za-z0-9_-' '-') ;;
    esac
  fi
fi

# ---- Scene list ---------------------------------------------------------------
# An enabled scene whose file is gone can fail the build (Unity reports "an incorrect path for a
# scene file") or ship a player without it. Errors here stop before the slow part.
SCENE_ERRORS=0
check_scenes() {
  ebs="$PROJECT/ProjectSettings/EditorBuildSettings.asset"
  if [ -n "$PROFILE_REL" ] && grep -q '^ *m_OverrideGlobalSceneList: *1' "$PROJECT/$PROFILE_REL"; then
    echo "unity-kit: note: $PROFILE_REL has its own scene list; the scene check is skipped."
    return
  fi
  if [ ! -f "$ebs" ]; then
    echo "error SCENE: ProjectSettings/EditorBuildSettings.asset is missing, so the build list is empty."
    SCENE_ERRORS=1; return
  fi
  # One line per entry: enabled|line of path|path|guid
  tr -d '\r' < "$ebs" | awk '
    /^  - enabled:/ { if (p != "") print en "|" ln "|" p "|" g; en = $3; p = ""; g = ""; ln = 0; next }
    /^    path:/    { p = $0; sub(/^    path: */, "", p); ln = NR; if (p == "") p = "(empty)"; next }
    /^    guid:/    { g = $2; next }
    /^  [^ -]/      { if (p != "") print en "|" ln "|" p "|" g; p = "" }
    END             { if (p != "") print en "|" ln "|" p "|" g }' > "$TMP/scenes"
  enabled=0
  while IFS='|' read -r en ln path guid; do
    if [ "$path" != "(empty)" ] && [ -f "$PROJECT/$path" ]; then
      [ "$en" = "1" ] && enabled=$((enabled + 1))
      continue
    fi
    moved=""
    [ -n "$guid" ] && moved=$(grep -rl --include='*.unity.meta' "^guid: $guid" "$PROJECT/Assets" 2>/dev/null | head -n 1)
    if [ -n "$moved" ]; then
      moved=${moved#"$PROJECT"/}; moved=${moved%.meta}
      echo "unity-kit: note: build list entry $path moved to $moved (same GUID); Unity follows the GUID."
      [ "$en" = "1" ] && enabled=$((enabled + 1))
    elif [ "$en" = "1" ]; then
      echo "ProjectSettings/EditorBuildSettings.asset($ln,1): error SCENE: enabled scene $path is in the build list but the file is gone."
      SCENE_ERRORS=$((SCENE_ERRORS + 1))
    else
      echo "unity-kit: note: disabled build list entry $path points to a deleted scene."
    fi
  done < "$TMP/scenes"
  if [ "$enabled" -eq 0 ] && [ "$SCENE_ERRORS" -eq 0 ]; then
    echo "ProjectSettings/EditorBuildSettings.asset(1,1): error SCENE: No enabled scenes in the build list."
    SCENE_ERRORS=1
  fi
  # Scenes loaded by name must be enabled in the list, or the player fails to load them at runtime.
  grep -rnoE --include='*.cs' 'SceneManager\.LoadScene(Async)? *\( *"[^"]+"' "$PROJECT/Assets" 2>/dev/null |
    sed "s#^$PROJECT/##" | while IFS= read -r hit; do
      scene=$(printf '%s' "$hit" | sed 's/.*( *"//; s/"$//')
      where=$(printf '%s' "$hit" | cut -d: -f1-2)
      awk -F'|' -v s="$scene" '$1 == "1" { n = $3; sub(/.*\//, "", n); sub(/\.unity$/, "", n); if (n == s || $3 == s || $3 == s ".unity") f = 1 } END { exit !f }' "$TMP/scenes" ||
        echo "unity-kit: warning: $where loads scene \"$scene\" by name, but it is not an enabled scene in the build list."
    done
}
check_scenes
if [ "$SCENE_ERRORS" -gt 0 ]; then
  echo "unity-kit: $SCENE_ERRORS scene list error(s); fix them before building. Not built."
  exit 1
fi

# ---- Editor and route ----------------------------------------------------------
# Unity leaves Temp/UnityLockfile behind after batch runs and crashes, so the
# file existing is not enough: check that a running Editor holds it.
editor_open() {
  lock="$PROJECT/Temp/UnityLockfile"
  [ -f "$lock" ] || return 1
  if [ -n "$LOCALAPPDATA" ]; then
    # Windows: the Editor opens the lock file without write sharing.
    ! ( : >> "$lock" ) 2>/dev/null
  elif command -v lsof >/dev/null 2>&1; then
    lsof "$lock" >/dev/null 2>&1
  else
    return 0
  fi
}
if editor_open; then
  echo "unity-kit: the Editor has $NAME open, and a player build runs Unity in batch mode, which can't open the project at the same time. Close the Editor (or build from File > Build Profiles), then check again. Not checked."
  exit 3
fi

UNITY=${UNITY_EDITOR_PATH:-}
if [ -z "$UNITY" ]; then
  for c in "/c/Program Files/Unity/Hub/Editor/$VERSION/Editor/Unity.exe" \
           "C:/Program Files/Unity/Hub/Editor/$VERSION/Editor/Unity.exe" \
           "/Applications/Unity/Hub/Editor/$VERSION/Unity.app/Contents/MacOS/Unity" \
           "$HOME/Unity/Hub/Editor/$VERSION/Editor/Unity"; do
    [ -x "$c" ] && UNITY=$c && break
  done
fi

# How Unity builds this target without a script: legacy desktop flags, or a build profile.
LEGACY=""; EXT=""
case "$TARGET" in
  StandaloneWindows64) LEGACY=-buildWindows64Player; EXT=.exe ;;
  StandaloneWindows) LEGACY=-buildWindowsPlayer; EXT=.exe ;;
  StandaloneOSX) LEGACY=-buildOSXUniversalPlayer; EXT=.app ;;
  StandaloneLinux64) LEGACY=-buildLinux64Player; EXT=.x86_64 ;;
  Android) EXT=.apk ;;
esac
# -buildTarget takes its own names; the Editor must start on the target, since switching
# target and building in one run fails while a domain reload is pending.
case "$TARGET" in
  StandaloneWindows64) BT=win64 ;; StandaloneWindows) BT=win ;; StandaloneOSX) BT=osxuniversal ;;
  StandaloneLinux64) BT=linux64 ;; WSAPlayer) BT=windowsstoreapps ;;
  *) BT=$(printf '%s' "$TARGET" | tr 'A-Z' 'a-z') ;;
esac
if [ -z "$METHOD" ] && [ -z "$PROFILE_REL" ] && [ -z "$LEGACY" ]; then
  if grep -qs "class UnityKitBuild" "$PROJECT/Assets/Editor/UnityKitBuild.cs"; then
    METHOD=$HELPER_METHOD
  else
    echo "unity-kit: NEEDS BUILD SCRIPT. Unity has no batch-mode build flag for $TARGET; only desktop targets have one (-buildWindows64Player and the like)."
    echo "unity-kit: options: a build profile for $TARGET (--profile), the project's own build method (--method Class.Method), or Assets/Editor/UnityKitBuild.cs (the build-fix skill offers to add it)."
    profiles=$(find "$PROJECT/Assets" -path '*Build Profiles*' -name '*.asset' 2>/dev/null | sed "s#^$PROJECT/#  #")
    [ -n "$profiles" ] && printf 'unity-kit: build profiles in this project:\n%s\n' "$profiles"
    echo "unity-kit: not checked."
    exit 3
  fi
fi

[ -n "$OUTPUT" ] || OUTPUT="$PROJECT/Builds/unity-kit/$TARGET/$NAME$EXT"
OUTPUT=$(printf '%s' "$OUTPUT" | sed 's#\\#/#g')
case "$OUTPUT" in /*|?:/*) ;; *) OUTPUT="$PROJECT/$OUTPUT" ;; esac
mkdir -p "$(dirname "$OUTPUT")"
# The log stays in the project's Logs/ folder, so Claude can read past the summary.
mkdir -p "$PROJECT/Logs"
LOG="$PROJECT/Logs/unity-kit-build-$TARGET.log"
rm -f "$LOG"

# ---- Log report ----------------------------------------------------------------
# Print the error lines of build log $1 that match build-patterns.txt, deduplicated, at most 20
# per class. Sets ERRORS to the number printed. Generic classes count only when nothing else matched.
report_from_log() {
  tr -d '\r' < "$1" | awk -v pats="$PATTERNS" '
    BEGIN {
      while ((getline l < pats) > 0) {
        sub(/\r$/, "", l)
        if (l ~ /^[ \t]*(#|$)/) continue
        split(l, f, " "); re = l; sub(/^[^ ]+ +[^ ]+ +/, "", re)
        n++; cls[n] = f[1]; ctx[n] = f[2] + 0; rx[n] = re
      }
    }
    function out(c, s,    file, t) {
      s = substr(s, 1, 400); sub(/^[ \t]+/, "", s)
      if (c == "SHADER") sub(/ at kernel [^ ]+/, "", s)   # a compute shader error repeats per kernel
      if (c == "CS") t = s
      else if (c == "SHADER" && match(s, / at [^ ()]+\([0-9]+\) \(on [^)]*\)$/)) {
        file = substr(s, RSTART + 4); sub(/ \(on .*$/, "", file); sub(/\)$/, ",1)", file)
        t = file ": error SHADER: " s
      } else t = "error " c ": " s
      if (t in seen) return
      seen[t] = 1
      if (c == "BUILD" || c == "MODULE") { gen[++ng] = t; return }
      if (++per[c] > 20) { if (per[c] == 21) more[c] = 1; return }
      spec[++ns] = t
    }
    pending > 0 && /^\* / { out(pc, buf); pending = 0 }   # next Gradle section
    pending > 0 { if ($0 !~ /^[ \t]*$/) { buf = buf " " $0; pending-- } if (pending == 0) out(pc, buf); next }
    {
      for (i = 1; i <= n; i++) if ($0 ~ rx[i]) {
        if (ctx[i] > 0) { pending = ctx[i]; pc = cls[i]; buf = $0 } else out(cls[i], $0)
        break
      }
    }
    END {
      if (pending > 0) out(pc, buf)
      if (ns > 0) { for (i = 1; i <= ns; i++) print spec[i]; for (c in more) print "unity-kit: more " c " errors not shown." }
      else for (i = 1; i <= ng; i++) print gen[i]
    }' > "$TMP/diag"
  ERRORS=$(grep -c 'error ' "$TMP/diag")
  cat "$TMP/diag"
}

# Build size from Unity's build report ("Complete build size    1.1 gb"), compared with the last
# successful build of this target when --state is given.
report_size() {
  size=$(tr -d '\r' < "$1" | sed -n 's/^Complete build size *//p' | tail -n 1)
  [ -n "$size" ] || return 0
  kb=$(printf '%s' "$size" | awk '{ u = tolower($2); m = (u == "gb") ? 1048576 : (u == "mb") ? 1024 : (u == "kb") ? 1 : 1 / 1024; printf "%.0f", $1 * m }')
  line="unity-kit: build size $size"
  if [ -n "$STATE" ]; then
    STATE=$(printf '%s' "$STATE" | sed 's#\\#/#g')
    mkdir -p "$STATE" 2>/dev/null
    f="$STATE/$(printf '%s' "$PROJECT" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-').build-$TARGET.size"
    if [ -f "$f" ]; then
      read -r old oldtext < "$f"
      line="$line (last build $oldtext, $(awk -v a="$kb" -v b="$old" 'BEGIN { d = (a - b) / 1024; printf "%s%.1f mb", (d >= 0 ? "+" : ""), d }'))"
    fi
    printf '%s %s\n' "$kb" "$size" > "$f"
  fi
  echo "$line."
}

finish() { # $1 = route name, $2 = Unity exit code
  if [ ! -s "$LOG" ]; then
    echo "unity-kit: Unity exited with code $2 via $1 and wrote no log. Not checked."
    exit 3
  fi
  # The Unity CLI hands Unity an access token, and Unity writes its command line into the log.
  if grep -q '^-accessToken' "$LOG"; then
    awk 'r { print "<removed by unity-kit>"; r = 0; next } { print } /^-accessToken/ { r = 1 }' "$LOG" > "$LOG.tmp" &&
      mv "$LOG.tmp" "$LOG"
  fi
  report_from_log "$LOG"
  if grep -q 'Build Finished, Result: Success' "$LOG" && [ "$2" -eq 0 ]; then
    [ "$ERRORS" -gt 0 ] && echo "unity-kit: warning: the lines above were logged, but did not fail the build."
    report_size "$LOG"
    # Unity's build size is uncompressed; an Android package is much smaller.
    case "$OUTPUT" in
      *.apk|*.aab) [ -f "$OUTPUT" ] &&
        echo "unity-kit: $(basename "$OUTPUT") is $(du -k "$OUTPUT" | awk '{ printf "%.1f mb", $1 / 1024 }') on disk." ;;
    esac
    echo "unity-kit: $TARGET build succeeded via $1: $OUTPUT"
    exit 0
  fi
  if [ "$ERRORS" -gt 0 ] || grep -q 'Build Finished, Result: Failure' "$LOG"; then
    if [ "$ERRORS" -eq 0 ]; then
      echo "unity-kit: no known error pattern matched. Last lines of the log:"
      tail -n 15 "$LOG"
    fi
    echo "unity-kit: $TARGET build failed via $1 ($ERRORS error line(s)). Full log: $LOG"
    exit 1
  fi
  echo "unity-kit: Unity exited with code $2 via $1 without a finished build in the log. Last lines:"
  tail -n 15 "$LOG"
  echo "unity-kit: not checked. Full log: $LOG"
  exit 3
}

# ---- 1. Unity CLI --------------------------------------------------------------
if [ "$UNITY_CLI" != none ] && command -v "$UNITY_CLI" >/dev/null 2>&1; then
  set -- build "$PROJECT" --output-path "$OUTPUT" --log-file "$LOG" --no-tail --allow-dirty-build --no-provenance --no-banner
  if [ -n "$PROFILE_REL" ]; then set -- "$@" --profile "$PROFILE_REL"; else set -- "$@" --target "$TARGET"; fi
  [ -n "$METHOD" ] && set -- "$@" --execute-method "$METHOD" --args "-unityKitTarget $TARGET"
  [ -n "$UNITY_EDITOR_PATH" ] && set -- "$@" --editor-path "$UNITY_EDITOR_PATH"
  "$UNITY_CLI" "$@" > "$TMP/cli.out" 2>&1
  rc=$?
  if [ -s "$LOG" ]; then
    finish "Unity CLI" "$rc"
  fi
  echo "unity-kit: note: the Unity CLI did not start a build (exit $rc): $(tail -n 1 "$TMP/cli.out" | cut -c1-200). Trying batch mode."
fi

# ---- 2. Batch mode -------------------------------------------------------------
if [ -z "$UNITY" ]; then
  echo "unity-kit: Unity $VERSION not found in the default Hub location, and no Unity CLI. Set UNITY_EDITOR_PATH. Not checked."
  exit 3
fi
set -- -batchmode -quit -projectPath "$PROJECT" -logFile "$LOG"
if [ -n "$METHOD" ]; then
  set -- "$@" -buildTarget "$BT" -executeMethod "$METHOD" -buildOutput "$OUTPUT" -unityKitTarget "$TARGET"
  [ -n "$PROFILE_REL" ] && set -- "$@" -activeBuildProfile "$PROFILE_REL"
elif [ -n "$PROFILE_REL" ]; then
  set -- "$@" -activeBuildProfile "$PROFILE_REL" -build "$OUTPUT"
else
  set -- "$@" "$LEGACY" "$OUTPUT"
fi
"$UNITY" "$@" >/dev/null 2>&1
rc=$?
finish "batch mode" "$rc"
