---
name: build-fix
description: Build a Unity player for one target and fix the build errors in a loop until it builds - C# that only breaks in player builds, shader errors, IL2CPP and stripping, Gradle and Android SDK, missing scenes in the build list. Run by the user only, because a player build takes minutes.
argument-hint: "<target or build profile: Android, StandaloneWindows64, StandaloneOSX, iOS, WebGL, \"Meta Quest\">"
disable-model-invocation: true
---

# Build and fix (Unity player)

Target: `$ARGUMENTS`. A BuildTarget name (`Android`, `StandaloneWindows64`, ...) goes to `--target`; anything else is a build profile name or `.asset` path and goes to `--profile`. If no target is given, list the profiles under `Assets/Settings/Build Profiles/` and ask which target to build.

1. Run with the Bash tool, exactly as written and on its own (no `; echo`, pipes or `&&`), in the background (`run_in_background`), because a build takes minutes; wait for it to finish. Its last line states the result: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/build-check.sh" --target <target> --state "${CLAUDE_PLUGIN_DATA}"` (or `--profile "<name>"` instead of `--target`).
   - Exit 0: built. Report the route, the build size line and the output path, then stop.
   - Exit 1: errors are listed as `File(line,col): error CLASS: message` or `error CLASS: message`. Go to step 2.
   - Exit 3 with **NEEDS BUILD SCRIPT**: see "Build script" below.
   - Other exit 3: not checked. Tell the user the reason it printed. If the Editor has the project open, ask them to close it and say so; never claim the project builds.
2. Read `m_EditorVersion` in `ProjectSettings/ProjectVersion.txt`. Every API you use in a fix must exist in that version. The full log is the `Full log:` path; read around an error when one line is not enough.
3. Fix each error by class, in the project's existing style:

   | Class | Fix |
   |---|---|
   | `CS` | Code that compiles in the Editor but not for this target. Check `#if UNITY_EDITOR` / `#if !UNITY_EDITOR` and platform defines (`UNITY_ANDROID`, `UNITY_IOS`, `UNITY_WEBGL`) around the line, `UnityEditor` APIs in runtime code (move them under `#if UNITY_EDITOR` or into an Editor-only asmdef), and asmdef `includePlatforms`/`excludePlatforms`. |
   | `SHADER` | The file named is the shader or compute shader; find it under `Assets/` or `Packages/` by name. `(on vulkan)`, `(on gles3)`, `(on metal)` is the graphics API that fails. Fix shaders under `Assets/`; for one in `Library/PackageCache`, tell the user which package. |
   | `IL2CPP` | Read the log lines before it. For types reached only by reflection or serialization, propose a `link.xml` under `Assets/` that preserves them, or `[Preserve]`. Ask before lowering Managed Stripping Level. |
   | `GRADLE` | The text after "What went wrong" is the cause: often duplicate Android libraries from two plugins, SDK version mismatches, or a custom Gradle template in `Assets/Plugins/Android/`. Ask before changing Player Settings SDK versions. |
   | `ANDROID-SDK`, `MODULE` | Machine setup, not code: the platform module, Android SDK & NDK Tools or OpenJDK is missing in Unity Hub, or Preferences > External Tools points at the wrong folder. Tell the user and stop the loop. |
   | `SCENE` | Edit `ProjectSettings/EditorBuildSettings.asset`: point the entry at the scene's current path and GUID (read the GUID from the scene's `.meta`), or remove the entry. Ask before removing. A warning about a scene loaded by name: tell the user, don't change code or the list on your own. |
   | `BUILD` | Generic failure. An exception from a build callback (`IPreprocessBuildWithReport`, `IPostprocessBuildWithReport`) names its class in the stack trace in the full log. |

4. Re-run step 1. Stop after 5 rounds with errors remaining and summarize what is left.

## Build script

Unity's batch-mode build flags only cover desktop targets. For other targets the script needs a build profile (`--profile`), the project's own build method (`--method Namespace.Class.Method`, look for `BuildPipeline.BuildPlayer` under `Editor` folders first), or a small Editor script. If the script listed build profiles, offer those first.

Otherwise, ask the user before adding `Assets/Editor/UnityKitBuild.cs`; never add it on your own. On a yes, write exactly this file and nothing else. Never write its `.meta`: the guard hook blocks it, and Unity creates it on import. Then re-run step 1; the script finds it.

```csharp
using System;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace UnityKit
{
    /// <summary>Batch-mode player build for unity-kit's build-check: the enabled scenes in Build Settings, for the target the Editor was launched on.</summary>
    public static class UnityKitBuild
    {
        public static void Build()
        {
            string output = Arg("-buildOutput");
            string requested = Arg("-unityKitTarget");
            BuildTarget target = EditorUserBuildSettings.activeBuildTarget;
            if (string.IsNullOrEmpty(output))
            {
                Fail("no -buildOutput argument.");
                return;
            }
            // Switching target and building in one run fails, so the Editor must start on the target (-buildTarget).
            if (!string.IsNullOrEmpty(requested) && !string.Equals(requested, target.ToString(), StringComparison.OrdinalIgnoreCase))
            {
                Fail($"the Editor started on {target}, not {requested}. Launch it with -buildTarget.");
                return;
            }
            string[] scenes = EditorBuildSettingsScene.GetActiveSceneList(EditorBuildSettings.scenes);
            if (scenes.Length == 0)
            {
                Fail("No enabled scenes in Build Settings.");
                return;
            }
            BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = output,
                target = target,
                targetGroup = BuildPipeline.GetBuildTargetGroup(target),
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        static string Arg(string name)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name) return args[i + 1];
            return null;
        }

        static void Fail(string message)
        {
            Debug.LogError("Error building Player: unity-kit: " + message);
            EditorApplication.Exit(1);
        }
    }
}
```
