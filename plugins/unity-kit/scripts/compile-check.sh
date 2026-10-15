#!/bin/sh
# unity-kit compile check.
# Usage: compile-check.sh [--batch] [project_dir]
#
# Routes, first one that works wins:
#   1. Unity-Skills REST server (localhost:8090-8100), read-only debug_check_compilation
#   2. Unity CLI: recompile a connected Editor, then read Editor.log
#   3. Editor.log of an Editor that has the project open
#   4. Batch mode (only with --batch, and only when the Editor does not have the project open)
#
# Exit: 0 compiles clean, 1 compile errors, 3 not checked (stale, unavailable, not a Unity project).
# Output: a short report for Claude. Error and warning lines are printed as Unity writes them.

BATCH=0
if [ "$1" = "--batch" ]; then BATCH=1; shift; fi
PROJECT=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
PROJECT=$(printf '%s' "$PROJECT" | sed 's#\\#/#g; s#/$##')

if [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
  echo "unity-kit: $PROJECT is not a Unity project root (no ProjectSettings/ProjectVersion.txt)."
  exit 3
fi

NAME=$(basename "$PROJECT")
VERSION=$(sed -n 's/^m_EditorVersion: *//p' "$PROJECT/ProjectSettings/ProjectVersion.txt" | tr -d '\r')
TMP=${TMPDIR:-/tmp}/unity-kit.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# Newest script-compilation input newer than file $1? Prints one path or nothing.
newer_sources() {
  find "$PROJECT/Assets" "$PROJECT/Packages" \( -name '*.cs' -o -name '*.asmdef' -o -name '*.asmref' \) \
    -newer "$1" 2>/dev/null | head -n 1
}

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

editor_log() {
  if [ -n "$LOCALAPPDATA" ]; then
    d=$LOCALAPPDATA
    command -v cygpath >/dev/null 2>&1 && d=$(cygpath -u "$LOCALAPPDATA")
    echo "$d/Unity/Editor/Editor.log"
  elif [ -d "$HOME/Library/Logs/Unity" ]; then
    echo "$HOME/Library/Logs/Unity/Editor.log"
  else
    echo "$HOME/.config/unity3d/Editor.log"
  fi
}

# Print the error/warning lines of the last compilation in log $1, deduplicated.
# Sets ERRORS to the error count.
report_from_log() {
  start=$(grep -n '\[ScriptCompilation\] Requested script compilation' "$1" | tail -n 1 | cut -d: -f1)
  [ -n "$start" ] || start=1
  tail -n +"$start" "$1" | grep -E '\([0-9]+,[0-9]+\): (error|warning) CS[0-9]+' | tr -d '\r' | sort -u > "$TMP/diag"
  ERRORS=$(grep -c ': error CS' "$TMP/diag")
  cat "$TMP/diag"
}

finish() { # $1 = route name
  if [ "$ERRORS" -gt 0 ]; then
    echo "unity-kit: $ERRORS compile error(s) via $1."
    exit 1
  fi
  echo "unity-kit: compiles clean via $1."
  exit 0
}

# ---- 1. Unity-Skills ---------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  q=$(printf '%s' "$NAME" | sed 's/ /%20/g')
  for port in 8090 8091 8092 8093 8094 8095 8096 8097 8098 8099 8100; do
    curl -s --max-time 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1 || continue
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      body=$(curl -s --max-time 5 -w '\n%{http_code}' -d '{}' \
        "http://127.0.0.1:$port/skill/debug_check_compilation?expectProject=$q")
      code=$(printf '%s' "$body" | tail -n 1)
      body=$(printf '%s' "$body" | sed '$d')
      [ "$code" = "200" ] || break
      printf '%s' "$body" | grep -q '"isCompiling": *true' || break
      sleep 3
    done
    [ "$code" = "200" ] || continue   # 409 = another project's Editor
    when=$(printf '%s' "$body" | sed -n 's/.*"finishedAtUtc": *"\([0-9-]*\)T\([0-9]*\):\([0-9]*\):\([0-9]*\).*/\1\2\3.\4/p' | tr -d '-')
    if [ -z "$when" ]; then
      echo "unity-kit: Unity-Skills on port $port has no finished compilation this session. Focus the Unity Editor so it compiles, then check again."
      exit 3
    fi
    TZ=UTC touch -t "$(printf '%s' "$when" | cut -c1-15)" "$TMP/compiled_at"
    stale=$(newer_sources "$TMP/compiled_at")
    if [ -n "$stale" ]; then
      echo "unity-kit: STALE. Unity last compiled before ${stale#"$PROJECT"/} changed. Focus the Unity Editor (or allow Unity-Skills debug_force_recompile), then check again."
      exit 3
    fi
    if printf '%s' "$body" | grep -q '"succeeded": *false'; then
      printf '%s\n' "$body" | cut -c1-4000
      echo "unity-kit: compile errors via Unity-Skills (port $port)."
      exit 1
    fi
    echo "unity-kit: compiles clean via Unity-Skills (port $port)."
    exit 0
  done
fi

LOG=$(editor_log)

# ---- 2. Unity CLI (live Editor with the Pipeline package) ---------------------
if editor_open && command -v unity >/dev/null 2>&1 &&
   unity status --json --no-banner 2>/dev/null | grep -q "$NAME"; then
  if unity command recompile --project-path "$PROJECT" --caller plugin --skill unity-kit --no-banner >/dev/null 2>&1; then
    i=0
    while [ $i -lt 40 ]; do
      unity command recompile_status --project-path "$PROJECT" --caller plugin --skill unity-kit --no-banner 2>/dev/null |
        grep -qi 'completed' && break
      sleep 3; i=$((i + 1))
    done
    if [ -f "$LOG" ]; then
      report_from_log "$LOG"
      finish "Unity CLI recompile + Editor.log"
    fi
  fi
fi

# ---- 3. Editor.log -----------------------------------------------------------
if editor_open; then
  if [ ! -f "$LOG" ]; then
    echo "unity-kit: the Editor has the project open but no Editor.log was found at $LOG."
    exit 3
  fi
  if ! head -n 80 "$LOG" | tr -d '\r' | sed 's#\\#/#g' | grep -qi "^$PROJECT\$"; then
    echo "unity-kit: Editor.log belongs to another Editor instance, not $NAME. Not checked."
    exit 3
  fi
  stale=$(newer_sources "$LOG")
  if [ -n "$stale" ]; then
    echo "unity-kit: STALE. Unity has logged nothing since ${stale#"$PROJECT"/} changed. Focus the Unity Editor so it recompiles, then check again."
    exit 3
  fi
  report_from_log "$LOG"
  echo "unity-kit: note: Editor.log shows the last compile Unity ran. If Unity has not refreshed since the last edit, focus the Editor and check again."
  finish "Editor.log"
fi

# ---- 4. Batch mode -----------------------------------------------------------
if [ "$BATCH" -ne 1 ]; then
  echo "unity-kit: no compile route available (no Unity-Skills server, Editor not open, batch mode not enabled). Not checked."
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
if [ -z "$UNITY" ]; then
  echo "unity-kit: Unity $VERSION not found in the default Hub location. Set UNITY_EDITOR_PATH. Not checked."
  exit 3
fi

"$UNITY" -batchmode -nographics -quit -projectPath "$PROJECT" -logFile "$TMP/batch.log" >/dev/null 2>&1
rc=$?
report_from_log "$TMP/batch.log"
if [ "$rc" -ne 0 ] && [ "$ERRORS" -eq 0 ]; then
  echo "unity-kit: batch mode exited with code $rc without compile errors in the log. Last lines:"
  tail -n 15 "$TMP/batch.log"
  exit 3
fi
finish "batch mode"
