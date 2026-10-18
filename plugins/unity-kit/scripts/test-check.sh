#!/bin/sh
# unity-kit test run check.
# Usage: test-check.sh [--platform editmode|playmode] [--filter F] [project_dir]
#   --platform P   run only EditMode or only PlayMode tests. Default: EditMode when an Editor-only test
#                  assembly exists, PlayMode when another test assembly exists, both when both exist
#   --filter F     run only tests whose full name matches F (Unity's -testFilter: names separated by ;
#                  or a regular expression)
#
# Test assemblies are asmdefs under Assets/ that reference UnityEngine.TestRunner (by name or GUID) or
# list UNITY_INCLUDE_TESTS in defineConstraints.
# Routes, first one that works wins:
#   1. Unity-Skills REST server (localhost:8090-8100): compile-check.sh first, then test_run and test_get_result
#   2. Unity CLI `unity test`
#   3. Batch mode: -runTests -testPlatform -testResults
# The CLI and batch mode launch Unity in batch mode, so neither can run while the Editor has the project open.
#
# Exit: 0 tests pass, 1 test failures or compile errors that stopped the run, 3 not checked (Editor open,
# no Unity, run error, not a Unity project), 4 no tests (no test assemblies, or the run found no tests).
# Output: a short report for Claude. One line per failure:
#   FAIL <test full name> | <message> | <first stack frame in the project, Assets/...cs:line>
# Results and logs stay in the project's Logs/ folder.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

PLATFORM=""; FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM=$2; shift ;;
    --filter) FILTER=$2; shift ;;
    *) break ;;
  esac
  shift
done
PROJECT=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
PROJECT=$(printf '%s' "$PROJECT" | sed 's#\\#/#g; s#/$##')
# Git Bash: /e/Game -> E:/Game, the form Unity writes in its logs and stack traces.
command -v cygpath >/dev/null 2>&1 && PROJECT=$(cygpath -m "$PROJECT")
UNITY_CLI=${UNITY_KIT_UNITY_CLI:-unity}   # tests point this at a fake, or at "none"
TIMEOUT=${UNITY_KIT_TEST_TIMEOUT:-1800}   # seconds to wait for a Unity-Skills test job

if [ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]; then
  echo "unity-kit: $PROJECT is not a Unity project root (no ProjectSettings/ProjectVersion.txt)."
  exit 3
fi
case $(printf '%s' "$PLATFORM" | tr 'A-Z' 'a-z') in
  "") ;;
  editmode) PLATFORM=EditMode ;;
  playmode) PLATFORM=PlayMode ;;
  *) echo "unity-kit: unknown --platform $PLATFORM; use editmode or playmode. Not checked."; exit 3 ;;
esac

NAME=$(basename "$PROJECT")
VERSION=$(sed -n 's/^m_EditorVersion: *//p' "$PROJECT/ProjectSettings/ProjectVersion.txt" | tr -d '\r')
TMP=${TMPDIR:-/tmp}/unity-kit-test.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# ---- Test assemblies ----------------------------------------------------------
# GUIDs of the UnityEngine.TestRunner and UnityEditor.TestRunner asmdefs, for asmdefs that reference by GUID.
EDIT_ASM=0; PLAY_ASM=0
find "$PROJECT/Assets" -name '*.asmdef' 2>/dev/null | grep -v -e '~/' -e '/\.' > "$TMP/asmdefs"
while IFS= read -r f; do
  flat=$(tr -d ' \t\r\n' < "$f")
  case "$flat" in
    *'"UnityEngine.TestRunner"'*|*'"UnityEditor.TestRunner"'*|*'"UNITY_INCLUDE_TESTS"'*|\
    *GUID:27619889b8ba8c24980f49ee34dbb44a*|*GUID:0acc523941302664db1f4e527237feb3*) ;;
    *) continue ;;
  esac
  case "$flat" in
    *'"includePlatforms":["Editor"]'*) EDIT_ASM=$((EDIT_ASM + 1)) ;;
    *) PLAY_ASM=$((PLAY_ASM + 1)) ;;
  esac
done < "$TMP/asmdefs"
if [ $((EDIT_ASM + PLAY_ASM)) -eq 0 ]; then
  echo "unity-kit: NO TESTS. No test assembly under Assets/ (an asmdef that references UnityEngine.TestRunner or lists UNITY_INCLUDE_TESTS in defineConstraints)."
  exit 4
fi
if [ -n "$PLATFORM" ]; then
  PLATFORMS=$PLATFORM
else
  PLATFORMS=""
  [ "$EDIT_ASM" -gt 0 ] && PLATFORMS=EditMode
  [ "$PLAY_ASM" -gt 0 ] && PLATFORMS="$PLATFORMS PlayMode"
fi

# ---- Reports ------------------------------------------------------------------
# awk functions shared by the XML and JSON readers: clean up a message, and find the first stack
# frame inside the project. proj is the project path in lower case.
AWKLIB='
function repl(s, a, b,    i, r) { r = ""; while ((i = index(s, a)) > 0) { r = r substr(s, 1, i - 1) b; s = substr(s, i + length(a)) } return r s }
function clean(s) { gsub(/[\r\n\t]+/, " ", s); gsub(/  +/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s); if (length(s) > 300) s = substr(s, 1, 297) "..."; return s }
function frame(st,    n, l, i, s, p, r) {
  n = split(st, l, "\n")
  for (i = 1; i <= n; i++) {
    s = l[i]; gsub(/\\/, "/", s)
    if ((p = index(tolower(s), proj "/")) > 0) {
      r = substr(s, p + length(proj) + 1)
      if (match(r, /^(Assets|Packages)\/[^:]*\.cs:[0-9]+/)) return substr(r, RSTART, RLENGTH)
    } else if (match(s, /(^|[ \/])Assets\/[^:]*\.cs:[0-9]+/)) {
      r = substr(s, RSTART, RLENGTH); sub(/^[ \/]/, "", r); return r
    }
  }
  return "no stack frame in the project"
}
function fail(name, msg, st) {
  msg = clean(msg); if (msg == "") msg = "(no message)"
  if (++nf <= 50) print "FAIL " name " | " msg " | " frame(st)
  else if (nf == 51) print "unity-kit: more failures not shown."
}'

# NUnit results XML $1 -> failure lines, then "COUNTS total passed failed skipped inconclusive".
# A failed test case is listed; so is a failed fixture or SetUpFixture whose own SetUp or TearDown
# failed (site is not Child or Parent).
report_xml() {
  tr -d '\r' < "$1" | awk -v proj="$(printf '%s' "$PROJECT" | tr 'A-Z' 'a-z')" "$AWKLIB"'
    function attr(s, n,    r) {
      if (!match(s, " " n "=\"[^\"]*\"")) return ""
      r = substr(s, RSTART + length(n) + 3, RLENGTH - length(n) - 4)
      r = repl(r, "&quot;", "\""); r = repl(r, "&apos;", "\047"); r = repl(r, "&lt;", "<"); r = repl(r, "&gt;", ">")
      return repl(r, "&amp;", "&")
    }
    # Other CDATA (a test'"'"'s <output>) can hold any text, even "<test-case": skip it.
    skip { if (index($0, "]]>")) skip = 0; next }
    !infail && (i = index($0, "<![CDATA[")) > 0 && !index(substr($0, i), "]]>") { skip = 1; next }
    /<test-run / && !counts { counts = attr($0, "total") " " attr($0, "passed") " " attr($0, "failed") " " attr($0, "skipped") " " attr($0, "inconclusive") }
    mode == "" && /<test-(case|suite) / {
      cur = attr($0, "fullname"); site = attr($0, "site")
      want = attr($0, "result") ~ /^Failed/ && (/<test-case / || (site != "" && site != "Child" && site != "Parent"))
    }
    mode == "" && want && /<failure>/ { infail = 1; msg = ""; st = "" }
    infail {
      line = $0
      if (mode == "" && (i = index(line, "<message><![CDATA[")) > 0) { mode = "m"; buf = substr(line, i + 18) }
      else if (mode == "" && (i = index(line, "<stack-trace><![CDATA[")) > 0) { mode = "s"; buf = substr(line, i + 22) }
      else if (mode != "") buf = buf "\n" line
      if (mode != "" && (e = index(buf, "]]>")) > 0) { if (mode == "m") msg = substr(buf, 1, e - 1); else st = substr(buf, 1, e - 1); mode = "" }
      if (mode == "" && index(line, "</failure>")) { fail(cur, msg, st); infail = 0 }
    }
    END { print "COUNTS " counts }'
}

# Unity-Skills test_get_result JSON $1 -> the same lines. Each entry of failedTestDetails has name,
# message and stackTrace strings.
report_json() {
  sed 's/.*"failedTestDetails"//' "$1" | grep -oE '"(name|message|stackTrace)": *"([^"\\]|\\.)*"' |
    awk -v proj="$(printf '%s' "$PROJECT" | tr 'A-Z' 'a-z')" "$AWKLIB"'
    function unjson(s) {
      sub(/^"[a-zA-Z]*": *"/, "", s); sub(/"$/, "", s)
      s = repl(s, "\\\\", "\001"); s = repl(s, "\\n", "\n"); s = repl(s, "\\r", ""); s = repl(s, "\\t", " ")
      s = repl(s, "\\\"", "\""); s = repl(s, "\\/", "/"); return repl(s, "\001", "\\")
    }
    /^"name"/ { if (have) fail(name, msg, st); have = 1; name = unjson($0); msg = ""; st = ""; next }
    /^"message"/ { msg = unjson($0); next }
    /^"stackTrace"/ { st = unjson($0) }
    END { if (have) fail(name, msg, st) }'
  num() { sed -n "s/.*\"$1\": *\([0-9][0-9]*\).*/\1/p" "$2" | head -n 1; }
  echo "COUNTS $(num totalTests "$1") $(num passedTests "$1") $(num failedTests "$1") $(num skippedTests "$1") $(num inconclusiveTests "$1")"
}

# Read a report on stdin, print it and add platform $1 to the summary. Sets RESULT to pass, fail or none.
# Feed it from a file, not a pipe: sh may run the last command of a pipe in a subshell.
SUMMARY=""; FAILS=0
summarize() {
  cat > "$TMP/report"
  grep -v '^COUNTS' "$TMP/report"
  set -- "$1" $(sed -n 's/^COUNTS //p' "$TMP/report")
  total=${2:-0}; passed=${3:-0}; failed=${4:-0}; skipped=${5:-0}
  nlines=$(grep -c '^FAIL ' "$TMP/report")
  [ "$failed" -ge "$nlines" ] 2>/dev/null || failed=$nlines
  if [ "$total" -eq 0 ] 2>/dev/null; then
    RESULT=none; SUMMARY="$SUMMARY, $1 no tests"
  elif [ "$failed" -gt 0 ]; then
    RESULT=fail; FAILS=$((FAILS + failed)); SUMMARY="$SUMMARY, $1 $passed/$total passed, $failed failed"
  else
    RESULT=pass; SUMMARY="$SUMMARY, $1 $passed/$total passed"
  fi
  [ "${skipped:-0}" -gt 0 ] 2>/dev/null && SUMMARY="$SUMMARY ($skipped skipped)"
  return 0
}

# Compile errors in log $1, deduplicated. Sets CS to their count.
compile_errors() {
  tr -d '\r' < "$1" | grep -E '\([0-9]+,[0-9]+\): error CS[0-9]+' | sort -u > "$TMP/cs"
  CS=$(grep -c . "$TMP/cs")
  cat "$TMP/cs"
}

OVERALL=none; ROUTE=""
record() { # pass | fail | none: the worst result wins
  case "$1" in
    fail) OVERALL=fail ;;
    pass) [ "$OVERALL" = none ] && OVERALL=pass ;;
  esac
}
finish() {
  SUMMARY=${SUMMARY#, }
  case "$OVERALL" in
    fail) echo "unity-kit: $FAILS test failure(s) via $ROUTE: $SUMMARY."; exit 1 ;;
    pass) echo "unity-kit: tests pass via $ROUTE: $SUMMARY."; exit 0 ;;
    *) echo "unity-kit: NO TESTS. The test assemblies have no tests to run via $ROUTE: $SUMMARY."; exit 4 ;;
  esac
}

# ---- 1. Unity-Skills ---------------------------------------------------------
# us <port> <skill> <json body>: response body in $TMP/us.json, HTTP status in US_CODE.
us() {
  US_CODE=$(curl -s --max-time 10 -o "$TMP/us.json" -w '%{http_code}' -d "$3" \
    "http://127.0.0.1:$1/skill/$2?expectProject=$(printf '%s' "$NAME" | sed 's/ /%20/g')")
}
jstr() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$TMP/us.json" | head -n 1; }
if command -v curl >/dev/null 2>&1; then
  for port in 8090 8091 8092 8093 8094 8095 8096 8097 8098 8099 8100; do
    curl -s --max-time 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1 || continue
    us "$port" test_get_last_result '{}'
    [ "$US_CODE" = "200" ] || continue   # 409 = another project's Editor
    ROUTE="Unity-Skills (port $port)"
    # Tests run on the scripts the Editor last compiled, so make sure that compile is current and clean.
    sh "$(dirname "$0")/compile-check.sh" "$PROJECT" > "$TMP/compile.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
      cat "$TMP/compile.out"
      [ "$rc" -eq 1 ] && { echo "unity-kit: compile errors stop the tests from running via $ROUTE. Fix them first."; exit 1; }
      echo "unity-kit: tests not run: the compile check above did not pass. Not checked."
      exit 3
    fi
    for plat in $PLATFORMS; do
      if [ -n "$FILTER" ]; then
        us "$port" test_run_by_name "{\"testName\":\"$(printf '%s' "$FILTER" | sed 's/["\\]/\\&/g')\",\"testMode\":\"$plat\"}"
      else
        us "$port" test_run "{\"testMode\":\"$plat\"}"
      fi
      job=$(jstr jobId)
      if [ -z "$job" ]; then
        code=$(jstr code); [ -n "$code" ] || code=$(jstr error)
        echo "unity-kit: Unity-Skills did not start the $plat tests (HTTP $US_CODE${code:+, $code}). In Approval mode test_run is refused; it needs Bypass mode or an Allowlist entry in the UnitySkills panel. Not checked."
        exit 3
      fi
      waited=0
      while :; do
        us "$port" test_get_result "{\"jobId\":\"$job\"}"   # a 503 during a domain reload is retried
        [ "$US_CODE" = "200" ] && grep -Eiq '"status": *"(completed|failed|cancelled|canceled|error)"' "$TMP/us.json" && break
        if [ "$waited" -ge "$TIMEOUT" ]; then
          echo "unity-kit: the $plat test job $job did not finish within $TIMEOUT s. Not checked."
          exit 3
        fi
        sleep 3; waited=$((waited + 3))
      done
      if ! grep -q '"totalTests"' "$TMP/us.json"; then
        cut -c1-2000 "$TMP/us.json"; echo
        echo "unity-kit: the $plat test job ended without results ($(jstr status)). Not checked."
        exit 3
      fi
      cp "$TMP/us.json" "$TMP/us-$plat.json"
      report_json "$TMP/us-$plat.json" > "$TMP/raw"; summarize "$plat" < "$TMP/raw"
      record "$RESULT"
    done
    finish
  done
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
  echo "unity-kit: the Editor has $NAME open, and without a Unity-Skills server tests run Unity in batch mode, which can't open the project at the same time. Close the Editor (or run the tests from Window > General > Test Runner), then check again. Not checked."
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
CLI=0
[ "$UNITY_CLI" != none ] && command -v "$UNITY_CLI" >/dev/null 2>&1 && CLI=1
if [ "$CLI" -eq 0 ] && [ -z "$UNITY" ]; then
  echo "unity-kit: Unity $VERSION not found in the default Hub location, and no Unity CLI. Set UNITY_EDITOR_PATH. Not checked."
  exit 3
fi

# The results and logs stay in the project's Logs/ folder, so Claude can read past the summary.
mkdir -p "$PROJECT/Logs"

# Run platform $1 through the Unity CLI or batch mode, and report it.
run_platform() {
  plat=$1
  xml="$PROJECT/Logs/unity-kit-tests-$plat.xml"
  log="$PROJECT/Logs/unity-kit-tests-$plat.log"
  rm -f "$xml" "$log"
  route=""
  if [ "$CLI" -eq 1 ]; then
    set -- test "$PROJECT" --mode "$plat" --output "$xml" --non-interactive --no-banner
    [ -n "$FILTER" ] && set -- "$@" --filter "$FILTER"
    [ -n "$UNITY_EDITOR_PATH" ] && set -- "$@" --editor-path "$UNITY_EDITOR_PATH"
    "$UNITY_CLI" "$@" > "$log" 2>&1
    rc=$?
    route="Unity CLI"
    if [ ! -s "$xml" ] && ! grep -q ': error CS[0-9]' "$log" && [ -n "$UNITY" ]; then
      echo "unity-kit: note: the Unity CLI wrote no test results (exit $rc): $(tr -d '\r' < "$log" | grep . | tail -n 1 | cut -c1-200). Trying batch mode."
      route=""
    fi
  fi
  if [ -z "$route" ]; then
    # No -quit: -runTests quits Unity when the run ends.
    set -- -batchmode -projectPath "$PROJECT" -runTests -testPlatform "$plat" -testResults "$xml" -logFile "$log"
    [ -n "$FILTER" ] && set -- "$@" -testFilter "$FILTER"
    "$UNITY" "$@" >/dev/null 2>&1
    rc=$?
    route="batch mode"
  fi
  ROUTE=$route
  # The Unity CLI hands Unity an access token, and Unity writes its command line into the log.
  if grep -q '^-accessToken' "$log" 2>/dev/null; then
    awk 'r { print "<removed by unity-kit>"; r = 0; next } { print } /^-accessToken/ { r = 1 }' "$log" > "$log.tmp" &&
      mv "$log.tmp" "$log"
  fi
  if [ -s "$xml" ]; then
    report_xml "$xml" > "$TMP/raw"; summarize "$plat" < "$TMP/raw"
    record "$RESULT"
    [ "$RESULT" = fail ] && echo "unity-kit: $plat results: $xml"
    return 0
  fi
  # No results: Unity stopped before the run. Compile errors are the usual reason.
  compile_errors "$log"
  if [ "$CS" -gt 0 ]; then
    echo "unity-kit: $CS compile error(s) stopped the $plat tests from running via $route. Fix them first. Full log: $log"
    exit 1
  fi
  echo "unity-kit: Unity exited with code $rc via $route without writing test results. Last lines of the log:"
  tr -d '\r' < "$log" | tail -n 15
  echo "unity-kit: not checked. Full log: $log"
  exit 3
}

for p in $PLATFORMS; do
  run_platform "$p"
done
finish
