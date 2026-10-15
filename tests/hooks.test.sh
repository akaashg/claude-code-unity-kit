#!/bin/sh
# Tests for the unity-kit hook scripts. Runs on Linux, macOS and Git Bash on Windows.
# Usage: sh tests/hooks.test.sh
# Builds a fake Unity project in a temp dir; needs no Unity install.

cd "$(dirname "$0")/.." || exit 1
SCRIPTS=plugins/unity-kit/scripts
T=${TMPDIR:-/tmp}/unity-kit-test.$$
P="$T/My Game"   # space on purpose
trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$P/ProjectSettings" "$P/Assets/Scripts" "$P/Library" "$P/Temp"
echo "m_EditorVersion: 6000.0.84f1" > "$P/ProjectSettings/ProjectVersion.txt"
echo "class A {}" > "$P/Assets/Scripts/A.cs"
echo "guid: 0" > "$P/Assets/Scripts/A.cs.meta"
echo "guid: 1" > "$P/Assets/Scripts.meta"

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $3)"; fails=$((fails + 1)); fi
}

guard() { # name expected-exit json
  printf '%s' "$3" | sh "$SCRIPTS/guard-paths.sh" 2>/dev/null
  check "guard: $1" "$2" "$?"
}

# Paths as JSON strings: forward slashes, and the Windows form with escaped backslashes.
fwd=$(printf '%s' "$P" | sed 's#"#\\"#g')
win=$(printf '%s' "$P" | sed 's#/#\\\\#g')

guard "edit existing .meta"              2 "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$fwd/Assets/Scripts/A.cs.meta\",\"old_string\":\"0\",\"new_string\":\"1\"}}"
guard "write new .meta"                  2 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fwd/Assets/Scripts/B.cs.meta\",\"content\":\"x\"}}"
guard "write under Library/"             2 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fwd/Library/x.txt\",\"content\":\"x\"}}"
guard "edit under Temp/ (pretty JSON)"   2 "$(printf '{\n  "tool_name": "Edit",\n  "tool_input": {\n    "file_path": "%s/Temp/x"\n  }\n}' "$fwd")"
guard "write .cs"                        0 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fwd/Assets/Scripts/B.cs\",\"content\":\"a \\\"q\\\" \\\\ b\"}}"
guard "content mentions file_path"       0 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fwd/Assets/C.cs\",\"content\":\"\\\"file_path\\\":\\\"x.meta\\\"\"}}"
guard ".meta outside a Unity project"    0 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$T/other/a.meta\",\"content\":\"x\"}}"
guard "no file_path"                     0 "{\"tool_name\":\"Write\",\"tool_input\":{}}"
U="$T/Café Jeu"   # non-ASCII project path
mkdir -p "$U/ProjectSettings" "$U/Assets"
cp "$P/ProjectSettings/ProjectVersion.txt" "$U/ProjectSettings/"
echo "guid: 3" > "$U/Assets/É.cs.meta"
guard "non-ASCII path, existing .meta"   2 "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$U/Assets/É.cs.meta\"}}"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    guard "Windows backslash path, .meta" 2 "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$win\\\\Assets\\\\Scripts\\\\A.cs.meta\"}}" ;;
esac

sh "$SCRIPTS/meta-check.sh" "$P" >/dev/null; check "meta-check: all paired" 0 "$?"
mv "$P/Assets/Scripts/A.cs" "$P/Assets/A.cs"
sh "$SCRIPTS/meta-check.sh" "$P" >/dev/null; check "meta-check: moved without .meta" 1 "$?"
mv "$P/Assets/Scripts/A.cs.meta" "$P/Assets/A.cs.meta"
echo "class N {}" > "$P/Assets/N.cs"
echo "ignored" > "$P/Assets/.hidden"; mkdir -p "$P/Assets/Docs~"; echo x > "$P/Assets/Docs~/a.txt"
sh "$SCRIPTS/meta-check.sh" "$P" >/dev/null; check "meta-check: new file only" 2 "$?"

sh "$SCRIPTS/compile-check.sh" "$P" >/dev/null; check "compile-check: no route, not checked" 3 "$?"
sh "$SCRIPTS/compile-check.sh" "$T" >/dev/null; check "compile-check: not a Unity project" 3 "$?"

stop() { # name expected-exit json
  printf '%s' "$3" | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_DATA="$T/data" sh "$SCRIPTS/stop-checks.sh" >/dev/null 2>&1
  check "stop: $1" "$2" "$?"
}
stop "new file only does not block" 0 '{"stop_hook_active":false}'
rm "$P/Assets/N.cs"; echo "guid: 2" > "$P/Assets/Gone.cs.meta"
stop "orphaned .meta blocks"         2 '{"stop_hook_active":false}'
stop "second stop never blocks"      0 '{"stop_hook_active":true}'

echo
[ "$fails" -eq 0 ] && echo "all hook tests passed" || echo "$fails hook test(s) failed"
[ "$fails" -eq 0 ]
