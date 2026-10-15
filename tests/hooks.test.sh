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

rm "$P/Assets/N.cs" "$P/Assets/.hidden"; rm -r "$P/Assets/Docs~"
mkdir -p "$P/Assets/Empty"; printf 'fileFormatVersion: 2\nguid: 4\nfolderAsset: yes\n' > "$P/Assets/Empty.meta"
rmdir "$P/Assets/Empty"   # as after a git clone: folder .meta kept, empty folder not
sh "$SCRIPTS/meta-check.sh" "$P" >/dev/null; check "meta-check: empty folder lost by git is not an orphan" 2 "$?"
rm "$P/Assets/Empty.meta"; echo "class N {}" > "$P/Assets/N.cs"

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

# Shared clean-compile state between compile-fix/precommit and the Stop hook, using a fake Unity
# for the batch route: it writes a clean or broken compile log and counts its calls.
rm -f "$P/Assets/Gone.cs.meta"
FAKE="$T/FakeUnity"
cat > "$FAKE" <<'EOF'
#!/bin/sh
log=""; while [ $# -gt 0 ]; do [ "$1" = "-logFile" ] && log=$2; shift; done
echo x >> "$FAKE_UNITY_CALLS"
echo "[ScriptCompilation] Requested script compilation because: test" > "$log"
if [ -n "$FAKE_UNITY_ERROR" ]; then
  echo 'Assets/A.cs(1,1): error CS0103: The name x does not exist in the current context' >> "$log"; exit 1
fi
exit 0
EOF
chmod +x "$FAKE"
export UNITY_EDITOR_PATH="$FAKE" FAKE_UNITY_CALLS="$T/calls"
S="$T/state"
calls() { [ -f "$T/calls" ] && wc -l < "$T/calls" | tr -d ' ' || echo 0; }

sh "$SCRIPTS/compile-check.sh" --batch --state "$S" "$P" >/dev/null; check "compile-check: clean via fake batch" 0 "$?"
before=$(calls)
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_DATA="$S" CLAUDE_PLUGIN_OPTION_BATCH_COMPILE=true sh "$SCRIPTS/stop-checks.sh" >/dev/null 2>&1
check "stop: after a clean compile-fix, no second compile" "$before" "$(calls)"
sleep 1; touch "$P/Assets/N.cs"
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_DATA="$S" CLAUDE_PLUGIN_OPTION_BATCH_COMPILE=true sh "$SCRIPTS/stop-checks.sh" >/dev/null 2>&1
check "stop: script changed, compiles again" "$((before + 1))" "$(calls)"
FAKE_UNITY_ERROR=1 sh "$SCRIPTS/compile-check.sh" --batch --state "$S" "$P" >/dev/null; check "compile-check: errors" 1 "$?"
before=$(calls)
printf '{"stop_hook_active":false}' | FAKE_UNITY_ERROR=1 CLAUDE_PROJECT_DIR="$P" CLAUDE_PLUGIN_DATA="$S" CLAUDE_PLUGIN_OPTION_BATCH_COMPILE=true sh "$SCRIPTS/stop-checks.sh" >/dev/null 2>&1
check "stop: errors left by compile-fix still block" 2 "$?"
check "stop: errors are compiled again, not skipped" "$((before + 1))" "$(calls)"

# Asset references: a git repo with a scene that references a project material, a package
# material, a package asmdef, a local package outside the project and a built-in resource.
unset UNITY_EDITOR_PATH
R="$T/Ref Game"
mkdir -p "$R/ProjectSettings" "$R/Assets/Art" "$R/Assets/Scenes" "$R/Assets/Code" "$R/Packages" \
  "$R/Library/PackageCache/com.x@1a2b/Runtime" "$T/Shared/com.local"
cp "$P/ProjectSettings/ProjectVersion.txt" "$R/ProjectSettings/"
printf '{\n  "dependencies": {\n    "com.local": "file:../../Shared/com.local"\n  }\n}\n' > "$R/Packages/manifest.json"
meta() { printf 'fileFormatVersion: 2\nguid: %s\n' "$2" > "$1.meta"; }
echo mat > "$R/Assets/Art/Rock.mat"; meta "$R/Assets/Art/Rock.mat" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
meta "$R/Library/PackageCache/com.x@1a2b/Runtime/Pkg.mat" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
meta "$R/Library/PackageCache/com.x@1a2b/Runtime/X.asmdef" cccccccccccccccccccccccccccccccc
meta "$T/Shared/com.local/Local.mat" 11111111111111111111111111111111
ref() { printf '  - {fileID: 2100000, guid: %s, type: 2}\n' "$@"; }
{ printf '%%YAML 1.1\n'; ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    11111111111111111111111111111111 0000000000000000f000000000000000; } > "$R/Assets/Scenes/Main.unity"
printf '{\n  "name": "Game",\n  "references": ["GUID:cccccccccccccccccccccccccccccccc"]\n}\n' > "$R/Assets/Code/Game.asmdef"
meta "$R/Assets/Code/Game.asmdef" dddddddddddddddddddddddddddddddd
printf 'Library/\n' > "$R/.gitignore"
git() { command git -C "$R" -c core.autocrlf=false -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
git init -q; git add -A; git commit -q -m fixture
refs() { # name expected-exit [args]
  n=$1; e=$2; shift 2
  sh "$SCRIPTS/ref-check.sh" "$@" "$R" >/dev/null; check "ref-check: $n" "$e" "$?"
}
refs "all references resolve" 0
refs "same result with the package cache" 0 --state "$T/refstate"
refs "cached package GUIDs" 0 --state "$T/refstate"
grep -qx bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$T"/refstate/*.pkg-guids; check "ref-check: package GUIDs written to the cache" 0 "$?"
rm "$R/Assets/Art/Rock.mat" "$R/Assets/Art/Rock.mat.meta"
refs "deleted referenced asset" 1
sh "$SCRIPTS/ref-check.sh" "$R" | grep -qF "Main.unity line 2: guid aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, was Assets/Art/Rock.mat at HEAD"
check "ref-check: names the file, line and old asset path" 0 "$?"
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$R" CLAUDE_PLUGIN_DATA="$T/data" sh "$SCRIPTS/stop-checks.sh" >/dev/null 2>&1
check "stop: broken reference blocks" 2 "$?"
git checkout HEAD -- Assets/Art
refs "restored with its .meta" 0
mkdir -p "$R/Assets/Docs~" "$R/Assets/.hidden"
{ printf '%%YAML 1.1\n'; ref 99999999999999999999999999999999; } > "$R/Assets/Docs~/Old.prefab"
cp "$R/Assets/Docs~/Old.prefab" "$R/Assets/.hidden/Old.prefab"
refs "folders Unity ignores are skipped" 0
rm -r "$R/Assets/Docs~" "$R/Assets/.hidden"
mkdir -p "$R/Assets/Plugins/Lib/.git"   # a nested repository: git grep would skip it, so find is used
rm "$R/Assets/Art/Rock.mat" "$R/Assets/Art/Rock.mat.meta"
refs "deleted referenced asset, find fallback" 1
git checkout HEAD -- Assets/Art; rm -r "$R/Assets/Plugins"
{ printf '%%YAML 1.1\n'; ref eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; } > "$R/Assets/Scenes/Level 2.prefab"
refs "invented GUID in a new file" 1
git add -A; git commit -q -m broken
refs "broken reference already committed" 0
echo "  m_Name: Level 2" >> "$R/Assets/Scenes/Level 2.prefab"
refs "unrelated edit to a file with an old broken reference" 0
printf '{\n  "name": "More",\n  "references": ["GUID:ffffffffffffffffffffffffffffffff"]\n}\n' > "$R/Assets/Code/More.asmdef"
refs "unknown GUID in a new asmdef does not block" 0
rm "$R/Assets/Code/More.asmdef"
{ printf '%%YAML 1.1\n'; ref ffffffffffffffffffffffffffffffff; } > "$R/Assets/Scenes/Level 3.prefab"
mv "$R/Library" "$R/Library.off"
refs "no PackageCache: can't tell" 2
mv "$R/Library.off" "$R/Library"; rm "$R/Assets/Scenes/Level 3.prefab"
rm -rf "$R/.git"
refs "no git: can't tell" 2
refs "not a Unity project" 3 "$T"
unset -f git

echo
[ "$fails" -eq 0 ] && echo "all hook tests passed" || echo "$fails hook test(s) failed"
[ "$fails" -eq 0 ]
