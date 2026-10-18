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

# Player builds, with a fake Unity that is both the Editor (batch mode) and the Unity CLI. It records
# its arguments and writes the build log for the failure class in FAKE_BUILD.
B="$T/Build Game"
mkdir -p "$B/ProjectSettings" "$B/Assets/Scenes" "$B/Assets/Scripts"
cp "$P/ProjectSettings/ProjectVersion.txt" "$B/ProjectSettings/"
echo scene > "$B/Assets/Scenes/Main.unity"; meta "$B/Assets/Scenes/Main.unity" 22222222222222222222222222222222
echo scene > "$B/Assets/Scenes/Extra.unity"; meta "$B/Assets/Scenes/Extra.unity" 33333333333333333333333333333333
ebs() { # enabled:path:guid ...
  printf '%%YAML 1.1\nEditorBuildSettings:\n  m_ObjectHideFlags: 0\n  serializedVersion: 2\n  m_Scenes:\n'
  for e in "$@"; do
    printf '  - enabled: %s\n    path: %s\n    guid: %s\n' "$(echo "$e" | cut -d: -f1)" "$(echo "$e" | cut -d: -f2)" "$(echo "$e" | cut -d: -f3)"
  done
  printf '  m_configObjects: {}\n'
}
ebs 1:Assets/Scenes/Main.unity:22222222222222222222222222222222 0:Assets/Scenes/Extra.unity:33333333333333333333333333333333 \
  > "$B/ProjectSettings/EditorBuildSettings.asset"
FB="$T/FakeBuild"
cat > "$FB" <<'EOF'
#!/bin/sh
: > "$FAKE_BUILD_ARGS"; for a in "$@"; do echo "$a" >> "$FAKE_BUILD_ARGS"; done
[ -n "$FAKE_CLI_NOSTART" ] && { echo "Error: editor not found"; exit 6; }
log=""; out=""; while [ $# -gt 0 ]; do case "$1" in -logFile|--log-file) log=$2 ;; -buildOutput) out=$2 ;; esac; shift; done
[ -n "$out" ] && printf 'apk' > "$out"
fail() { printf '%s\nBuild Finished, Result: Failure.\n' "$1" > "$log"; exit 1; }
case "${FAKE_BUILD:-clean}" in
  clean) printf 'COMMAND LINE ARGUMENTS:\r\n-accessToken\r\nSECRET-TOKEN\r\n-logFile\r\nBuild Report\nComplete build size    %s\nBuild Finished, Result: Success.\n' "${FAKE_SIZE:-1.0 gb}" > "$log" ;;
  clean-shader) printf "Shader error in 'Fog': undeclared identifier 'x' at line 3 (on gles3)\nBuild Finished, Result: Success.\n" > "$log" ;;
  cs) fail "Assets/Scripts/Net.cs(12,9): error CS0103: The name 'EditorPrefs' does not exist in the current context
Error building Player because scripts had compiler errors" ;;
  shader) fail "Shader error in 'EnvironmentMapping': syntax error: unexpected token 'if' at kernel Raymarch at EnvironmentMapping.compute(74) (on vulkan)
Shader error in 'EnvironmentMapping': syntax error: unexpected token 'if' at kernel DilateDepthStep at EnvironmentMapping.compute(74) (on vulkan)" ;;
  il2cpp) fail "Fatal error in Unity CIL Linker
Exception: UnityLinker.exe did not run properly!" ;;
  gradle) printf 'FAILURE: Build failed with an exception.\r\n\r\n* What went wrong:\r\nExecution failed for task :launcher:checkReleaseDuplicateClasses.\r\n> Duplicate class com.google.Foo found in modules a.aar and b.aar\r\n\r\n* Try:\r\nCommandInvokationFailure: Gradle build failed.\r\nBuild Finished, Result: Failure.\r\n' > "$log"; exit 1 ;;
  sdk) fail "Unable to detect SDK in the selected directory." ;;
  module) fail "Error building player because build target was unsupported" ;;
  unknown) fail "Something new went wrong" ;;
  crash) echo "Aborting batchmode due to failure" > "$log"; exit 1 ;;
esac
exit 0
EOF
chmod +x "$FB"
export UNITY_EDITOR_PATH="$FB" UNITY_KIT_UNITY_CLI=none FAKE_BUILD_ARGS="$T/build-args" FAKE_BUILD= FAKE_SIZE= FAKE_CLI_NOSTART=
BS="$T/buildstate"
build() { # name expected-exit [args]
  n=$1; e=$2; shift 2
  sh "$SCRIPTS/build-check.sh" "$@" "$B" > "$T/build-out"; check "build-check: $n" "$e" "$?"
}
has() { grep -qF -- "$2" "$T/build-out"; check "build-check: $1" 0 "$?"; }
arg() { grep -qxF -- "$2" "$T/build-args"; check "build-check: $1" 0 "$?"; }

build "not a Unity project" 3 --target StandaloneWindows64 "$T"
sh "$SCRIPTS/build-check.sh" "$B" > /dev/null; check "build-check: no target, not checked" 3 "$?"
build "clean desktop build" 0 --target StandaloneWindows64 --state "$BS"
arg "desktop target uses the legacy build flag" -buildWindows64Player
has "reports the build size" "build size 1.0 gb."
check "build-check: access token removed from the log" 0 "$(grep -c SECRET-TOKEN "$B/Logs/unity-kit-build-StandaloneWindows64.log")"
grep -q '^<removed by unity-kit>' "$B/Logs/unity-kit-build-StandaloneWindows64.log"; check "build-check: rest of the log kept" 0 "$?"
FAKE_SIZE="1.1 gb"; build "second clean build" 0 --target StandaloneWindows64 --state "$BS"; FAKE_SIZE=
has "shows the change from the last build" "build size 1.1 gb (last build 1.0 gb, +102.4 mb)."
FAKE_BUILD=clean-shader; build "errors logged by a successful build don't fail it" 0 --target StandaloneWindows64
has "but are listed" "error SHADER: Shader error in 'Fog'"
for c in cs:"Assets/Scripts/Net.cs(12,9): error CS0103:" \
         shader:"EnvironmentMapping.compute(74,1): error SHADER: Shader error in 'EnvironmentMapping'" \
         il2cpp:"error IL2CPP: Fatal error in Unity CIL Linker" \
         gradle:"error GRADLE: * What went wrong: Execution failed for task :launcher:checkReleaseDuplicateClasses. > Duplicate class com.google.Foo found in modules a.aar and b.aar" \
         sdk:"error ANDROID-SDK: Unable to detect SDK" \
         module:"error MODULE: Error building player because build target was unsupported" \
         unknown:"error BUILD: Build Finished, Result: Failure."; do
  FAKE_BUILD=${c%%:*}; build "${c%%:*} failure" 1 --target StandaloneWindows64
  has "${c%%:*} error line" "${c#*:}"
done
FAKE_BUILD=shader; build "shader failure, one line for all kernels" 1 --target StandaloneWindows64
check "build-check: one line per distinct error" 1 "$(grep -c 'error SHADER' "$T/build-out")"
FAKE_BUILD=gradle; build "gradle failure, cause only" 1 --target StandaloneWindows64
check "build-check: Gradle cause stops at the next section" 0 "$(grep -c 'Try:' "$T/build-out")"
FAKE_BUILD=cs; build "generic lines hidden when a class matched" 1 --target StandaloneWindows64
check "build-check: no generic BUILD line next to a CS error" 0 "$(grep -c 'error BUILD' "$T/build-out")"
FAKE_BUILD=crash; build "Unity exits without a finished build" 3 --target StandaloneWindows64; FAKE_BUILD=

build "Android without a build method" 3 --target Android
has "says a build script is needed" "NEEDS BUILD SCRIPT"
mkdir -p "$B/Assets/Editor"; echo "public static class UnityKitBuild {}" > "$B/Assets/Editor/UnityKitBuild.cs"
build "Android with UnityKitBuild.cs" 0 --target Android
arg "uses the kit's build method" UnityKit.UnityKitBuild.Build
arg "starts the Editor on the target" android
has "prints the package size on disk" "Build Game.apk is "
rm -r "$B/Assets/Editor"
mkdir -p "$B/Assets/Settings/Build Profiles"
printf 'MonoBehaviour:\n  m_Name: Quest\n  m_BuildTarget: 13\n  m_OverrideGlobalSceneList: 0\n' > "$B/Assets/Settings/Build Profiles/Quest.asset"
build "build profile by name" 0 --profile Quest
arg "passes the profile path" "Assets/Settings/Build Profiles/Quest.asset"
grep -q 'Builds/unity-kit/Android/Build Game.apk$' "$T/build-args"; check "build-check: profile target read from m_BuildTarget" 0 "$?"
build "unknown profile" 3 --profile Nope

UNITY_KIT_UNITY_CLI="$FB"; build "Unity CLI route" 0 --target StandaloneWindows64
has "names the Unity CLI route" "via Unity CLI"
arg "Unity CLI gets the target" StandaloneWindows64
FAKE_CLI_NOSTART=1; build "Unity CLI can't start: no batch fallback with the same fake" 3 --target StandaloneWindows64; FAKE_CLI_NOSTART=; UNITY_KIT_UNITY_CLI=none
has "says it falls back to batch mode" "Trying batch mode."

ebs 1:Assets/Scenes/Gone.unity:44444444444444444444444444444444 1:Assets/Scenes/Main.unity:22222222222222222222222222222222 \
  > "$B/ProjectSettings/EditorBuildSettings.asset"
: > "$T/build-args"
build "enabled scene deleted" 1 --target StandaloneWindows64
has "names the build list line" "ProjectSettings/EditorBuildSettings.asset(7,1): error SCENE: enabled scene Assets/Scenes/Gone.unity"
check "build-check: no build after a scene error" 0 "$(wc -l < "$T/build-args" | tr -d ' ')"
ebs 1:Assets/Old/Main.unity:22222222222222222222222222222222 > "$B/ProjectSettings/EditorBuildSettings.asset"
build "scene moved with its .meta" 0 --target StandaloneWindows64
ebs 0:Assets/Scenes/Main.unity:22222222222222222222222222222222 > "$B/ProjectSettings/EditorBuildSettings.asset"
build "no enabled scenes" 1 --target StandaloneWindows64
has "says no enabled scenes" "error SCENE: No enabled scenes"
ebs 1:Assets/Scenes/Main.unity:22222222222222222222222222222222 0:Assets/Scenes/Extra.unity:33333333333333333333333333333333 \
  > "$B/ProjectSettings/EditorBuildSettings.asset"
echo 'class L { void A() { SceneManager.LoadScene("Extra"); SceneManager.LoadScene("Main"); } }' > "$B/Assets/Scripts/L.cs"
build "scene loaded by name but disabled" 0 --target StandaloneWindows64
has "warns about the disabled scene" 'Assets/Scripts/L.cs:1 loads scene "Extra" by name'
check "build-check: no warning for an enabled scene" 1 "$(grep -c 'loads scene' "$T/build-out")"
unset UNITY_EDITOR_PATH UNITY_KIT_UNITY_CLI

# Test runs, with a fake Unity that is both the Editor (batch mode) and the Unity CLI. It records its
# arguments and writes NUnit results XML like Unity's for the case in FAKE_TESTS. A fake curl stands in
# for the Unity-Skills server, and answers nothing unless FAKE_US is set, so a real server is never used.
TP="$T/Test Game"
mkdir -p "$TP/ProjectSettings" "$TP/Assets/Scripts" "$T/bin"
cp "$P/ProjectSettings/ProjectVersion.txt" "$TP/ProjectSettings/"
FT="$T/FakeTest"
cat > "$FT" <<'EOF'
#!/bin/sh
printf '%s\n' "--" "$@" >> "$FAKE_TEST_ARGS"
[ -n "$FAKE_CLI_NOSTART" ] && [ "$1" = test ] && { echo "Error: editor not found"; exit 6; }
xml=""; log=/dev/stdout; proj=""   # the Unity CLI prints to the console
[ "$1" = test ] && proj=$2
while [ $# -gt 0 ]; do case "$1" in -testResults|--output) xml=$2 ;; -logFile) log=$2 ;; -projectPath) proj=$2 ;; esac; shift; done
win=$(printf '%s' "$proj" | sed 's#/#\\#g')   # Unity writes Windows paths with backslashes
run() { # total passed failed
  printf '<?xml version="1.0" encoding="utf-8"?>\n<test-run id="2" testcasecount="%s" result="Passed" total="%s" passed="%s" failed="%s" inconclusive="0" skipped="0" asserts="0" engine-version="3.5.0.0" duration="0.5">\n' "$1" "$1" "$2" "$3"
}
case "${FAKE_TESTS:-pass}" in
  pass) { run 2 2 0; printf '  <test-suite type="TestSuite" id="1000" name="Test Game" fullname="Test Game" result="Passed">\n    <test-case id="1001" name="A" fullname="Tests.T.A" result="Passed" />\n    <test-case id="1002" name="B" fullname="Tests.T.B" result="Passed">\n      <properties />\n    </test-case>\n  </test-suite>\n</test-run>\n'; } > "$xml" ;;
  fail) { run 3 1 2; cat <<XML
  <test-suite type="TestSuite" id="1000" name="Test Game" fullname="Test Game" result="Failed" site="Child">
    <failure>
      <message><![CDATA[One or more child tests had errors]]></message>
    </failure>
    <test-suite type="TestFixture" id="1004" name="MathTests" fullname="Tests.MathTests" result="Failed" site="Child">
      <test-case id="1001" name="Adds two numbers" fullname="Tests.MathTests.Adds two numbers" methodname="Add" classname="Tests.MathTests" runstate="Runnable" result="Failed" duration="0.01" asserts="0">
        <properties />
        <failure>
          <message><![CDATA[  Expected: 4
  But was:  5
]]></message>
          <stack-trace><![CDATA[at Tests.MathTests.Add () [0x00001] in $win\\Assets\\Tests\\Editor\\MathTests.cs:12
]]></stack-trace>
        </failure>
        <output><![CDATA[logged: <test-case fullname="Not.A.Test" result="Failed">
<failure>
]]></output>
      </test-case>
      <test-case id="1002" name="Divide(&quot;a b&quot;,0)" fullname="Tests.MathTests.Divide(&quot;a b&quot;,0)" result="Failed" label="Error">
        <failure>
          <message><![CDATA[System.DivideByZeroException : Attempted to divide by zero.]]></message>
          <stack-trace><![CDATA[  at Calc.Divide (System.Int32 a, System.Int32 b) [0x00001] in $win\\Assets\\Scripts\\Calc.cs:7
  at Tests.MathTests.Divide (System.String s, System.Int32 b) [0x00001] in $win\\Assets\\Tests\\Editor\\MathTests.cs:20]]></stack-trace>
        </failure>
      </test-case>
      <test-case id="1003" name="Passes" fullname="Tests.MathTests.Passes" result="Passed" />
    </test-suite>
  </test-suite>
</test-run>
XML
  } | sed 's/$/\r/' > "$xml" ;;   # CRLF, as Unity writes it on Windows
  empty) { run 0 0 0; printf '</test-run>\n'; } > "$xml" ;;
  compile) printf 'Assets/Scripts/Calc.cs(3,5): error CS0103: The name x does not exist in the current context\r\nScripts had compilation errors.\r\nTest run completed. Exiting with code 3 (RunError). Scripts had compilation errors.\r\n' >> "$log"; exit 3 ;;
  crash) echo "Aborting batchmode due to failure" >> "$log"; exit 1 ;;
esac
exit 0
EOF
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
out=""; fmt=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; -w) fmt=$2; shift ;; -d|--max-time) shift ;; http*) url=$1 ;; esac; shift; done
[ -n "$FAKE_US" ] || exit 7   # connection refused
url=${url%%\?*}
case "$url" in
  */health) body='{"status":"ok"}' ;;
  */debug_check_compilation)
    if [ "$FAKE_US" = compile ]; then body='{"succeeded": false, "finishedAtUtc": "2099-01-01T00:00:00Z", "errors": ["Assets/Scripts/Calc.cs(3,5): error CS0103: The name x does not exist"]}'
    else body='{"succeeded": true, "isCompiling": false, "finishedAtUtc": "2099-01-01T00:00:00Z"}'; fi ;;
  */test_run|*/test_run_by_name) echo "$url" >> "$FAKE_TEST_ARGS"
    if [ "$FAKE_US" = refuse ]; then body='{"success": false, "code": "MODE_FORBIDDEN"}'
    else body='{"success": true, "status": "accepted", "jobId": "job-1"}'; fi ;;
  */test_get_result) w=$(printf '%s' "$FAKE_PROJECT" | sed 's#/#\\\\#g')   # JSON-escaped backslashes
    body='{"success": true, "jobId": "job-1", "status": "completed", "totalTests": 3, "passedTests": 2, "failedTests": 1, "skippedTests": 0, "failedTestNames": ["Tests.MathTests.Adds two numbers"], "failedTestDetails": [{"name": "Tests.MathTests.Adds two numbers", "resultState": "Failed", "message": "  Expected: \"4\"\n  But was:  5\n", "stackTrace": "at Tests.MathTests.Add () [0x00001] in '"$w"'\\Assets\\Tests\\Editor\\MathTests.cs:12\n", "output": ""}]}' ;;
  *) body='{}' ;;
esac
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
case "$fmt" in '\n'*) printf '\n200' ;; ?*) printf '200' ;; esac
EOF
chmod +x "$FT" "$T/bin/curl"
OLDPATH=$PATH; PATH="$T/bin:$PATH"
export UNITY_EDITOR_PATH="$FT" UNITY_KIT_UNITY_CLI=none FAKE_TEST_ARGS="$T/test-args" FAKE_TESTS= FAKE_US= FAKE_CLI_NOSTART=
FAKE_PROJECT=$TP; command -v cygpath >/dev/null 2>&1 && FAKE_PROJECT=$(cygpath -m "$TP"); export FAKE_PROJECT
tests() { # name expected-exit [args]
  n=$1; e=$2; shift 2
  : > "$T/test-args"
  sh "$SCRIPTS/test-check.sh" "$@" "$TP" > "$T/test-out"; check "test-check: $n" "$e" "$?"
}
thas() { grep -qF -- "$2" "$T/test-out"; check "test-check: $1" 0 "$?"; }
targ() { grep -qxF -- "$2" "$T/test-args"; check "test-check: $1" 0 "$?"; }

tests "not a Unity project" 3 "$T"
tests "no asmdefs: no tests" 4
thas "says no tests" "NO TESTS"
echo '{ "name": "Game" }' > "$TP/Assets/Scripts/Game.asmdef"
tests "asmdef without test references: no tests" 4
mkdir -p "$TP/Assets/Tests/Editor"
printf '{\r\n    "name": "EditTests",\r\n    "references": [\r\n        "UnityEngine.TestRunner",\r\n        "UnityEditor.TestRunner"\r\n    ],\r\n    "includePlatforms": [\r\n        "Editor"\r\n    ],\r\n    "defineConstraints": [\r\n        "UNITY_INCLUDE_TESTS"\r\n    ]\r\n}\r\n' > "$TP/Assets/Tests/Editor/EditTests.asmdef"
tests "passing EditMode tests" 0
thas "summary names the route and counts" "tests pass via batch mode: EditMode 2/2 passed."
targ "batch mode runs tests" -runTests
targ "Editor-only test assembly runs EditMode" EditMode
check "test-check: PlayMode not run without a runtime test assembly" 0 "$(grep -cx PlayMode "$T/test-args")"
check "test-check: no -quit with -runTests" 0 "$(grep -cx -- -quit "$T/test-args")"
check "test-check: results XML kept in Logs/" 0 "$([ -s "$TP/Logs/unity-kit-tests-EditMode.xml" ]; echo $?)"
FAKE_TESTS=fail; tests "failing tests (CRLF results)" 1
thas "test name with spaces, message on one line, frame in the project" "FAIL Tests.MathTests.Adds two numbers | Expected: 4 But was: 5 | Assets/Tests/Editor/MathTests.cs:12"
thas "XML entities decoded, first frame in the project" 'FAIL Tests.MathTests.Divide("a b",0) | System.DivideByZeroException : Attempted to divide by zero. | Assets/Scripts/Calc.cs:7'
check "test-check: one line per failed test, none for suites or output text" 2 "$(grep -c '^FAIL ' "$T/test-out")"
check "test-check: no carriage returns in the report" 0 "$(tr -cd '\r' < "$T/test-out" | wc -c | tr -d ' ')"
thas "summary counts failures" "2 test failure(s) via batch mode: EditMode 1/3 passed, 2 failed."
FAKE_TESTS=compile; tests "compile errors stop the run" 1
thas "lists the compile error" "Assets/Scripts/Calc.cs(3,5): error CS0103:"
thas "says compile errors stopped the tests" "1 compile error(s) stopped the EditMode tests"
FAKE_TESTS=empty; tests "test assembly without tests" 4
FAKE_TESTS=crash; tests "Unity exits without results" 3
FAKE_TESTS=; tests "filter" 0 --filter "Tests.MathTests;Tests.T"
targ "filter passed to Unity" "Tests.MathTests;Tests.T"
tests "forced PlayMode" 0 --platform playmode
targ "PlayMode platform passed" PlayMode
tests "unknown platform" 3 --platform both
mkdir -p "$TP/Assets/Tests/Runtime"
echo '{"name":"RuntimeTests","references":["GUID:27619889b8ba8c24980f49ee34dbb44a"],"includePlatforms":[]}' > "$TP/Assets/Tests/Runtime/RuntimeTests.asmdef"
tests "runtime test assembly by GUID adds PlayMode" 0
thas "both platforms in the summary" "EditMode 2/2 passed, PlayMode 2/2 passed."

UNITY_KIT_UNITY_CLI="$FT"; tests "Unity CLI route" 0 --platform editmode
thas "names the Unity CLI route" "via Unity CLI"
targ "Unity CLI gets the mode" EditMode
targ "Unity CLI gets the results path" "$FAKE_PROJECT/Logs/unity-kit-tests-EditMode.xml"
FAKE_TESTS=compile; tests "compile errors through the Unity CLI" 1 --platform editmode; FAKE_TESTS=
thas "Unity CLI compile error listed" "error CS0103"
FAKE_CLI_NOSTART=1; tests "Unity CLI can't start: falls back to batch mode" 0 --platform editmode; FAKE_CLI_NOSTART=
thas "says it falls back" "Trying batch mode."
thas "batch mode ran" "via batch mode"
UNITY_KIT_UNITY_CLI=none

FAKE_US=1; tests "Unity-Skills route" 1 --platform editmode
thas "names the Unity-Skills route" "via Unity-Skills (port 8090)"
thas "failure from JSON, escapes decoded" 'FAIL Tests.MathTests.Adds two numbers | Expected: "4" But was: 5 | Assets/Tests/Editor/MathTests.cs:12'
grep -q '/skill/test_run$' "$T/test-args"; check "test-check: Unity-Skills test_run called" 0 "$?"
check "test-check: Unity-Skills route does not launch Unity" 0 "$(grep -c -- -runTests "$T/test-args")"
tests "Unity-Skills with a filter" 1 --platform editmode --filter Tests.MathTests
grep -q '/skill/test_run_by_name$' "$T/test-args"; check "test-check: filter uses test_run_by_name" 0 "$?"
FAKE_US=refuse; tests "Unity-Skills refuses test_run" 3 --platform editmode
thas "explains the refusal" "MODE_FORBIDDEN"
FAKE_US=compile; tests "Unity-Skills: compile errors first" 1 --platform editmode
thas "Unity-Skills compile error listed" "Assets/Scripts/Calc.cs(3,5): error CS0103"
FAKE_US=
PATH=$OLDPATH
unset UNITY_EDITOR_PATH UNITY_KIT_UNITY_CLI

echo
[ "$fails" -eq 0 ] && echo "all hook tests passed" || echo "$fails hook test(s) failed"
[ "$fails" -eq 0 ]
