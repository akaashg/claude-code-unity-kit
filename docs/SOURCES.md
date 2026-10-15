# Where each rule comes from

Every rule, hook, skill and agent check in unity-kit traces to the author's own Unity workflow, collected in an interview on 2026-10-14. Nothing here is copied from a client project. If a change adds a rule, add its source to this table.

| Piece | Rule or check | Source |
|---|---|---|
| `guard-paths` hook | Block edits to existing `.meta` files | Interview: the one file type Claude must never edit by hand |
| `guard-paths` hook | Block writing new `.meta` files | Interview: Claude breaks `.meta`/GUIDs when moving or renaming assets |
| `guard-paths` hook | Block edits under `Library/` and `Temp/` | Original brief for the kit |
| `stop-checks` hook, `meta-check.sh` | Orphaned `.meta` / asset without `.meta` | Interview: breaks `.meta`/GUIDs; pre-commit check "every asset has its .meta" |
| `stop-checks` hook, `ref-check.sh` | Block references that broke since the last commit (deleted asset, hand-written GUID) | Interview: Claude breaks `.meta`/GUIDs when moving or renaming assets; the scenes and prefabs that use the asset are where it shows up as Missing |
| `stop-checks` hook, `compile-check.sh` | Compile gate at end of turn | Interview: pre-commit check "compiles with zero errors" |
| `compile-check.sh` routes | Unity-Skills, Unity CLI, Editor.log, batch mode | Interview: how compile errors reach Claude today |
| `build-check.sh`, `build-fix` skill | Build a player, fix, rebuild; user-triggered only | Roadmap PROD-53 (the build stage of the author's pipeline). Not in the Stop hook or `precommit` because a player build takes minutes (66 s for the author's Android build of Arena Calibration System) |
| `build-check.sh` routes | `unity build`, then batch mode; Editor must be closed | Unity CLI `unity build --list-targets` (1.0.0-beta.13): only desktop targets build without `--execute-method` or a build profile. Unity 6000.0 manual, [command line arguments](https://docs.unity3d.com/6000.0/Documentation/Manual/EditorCommandLineArguments.html): `-build*Player` flags exist only for Windows, macOS and Linux; `-activeBuildProfile` + `-build` build from a profile |
| `UnityKitBuild.cs` (offered by `build-fix`) | Launch the Editor on the target with `-buildTarget`, never switch target in the build call | Unity issue [13017](https://issuetracker.unity.com/issues/13017/error-building-player-a-domain-reload-is-pending-when-launching-a-batch-build-via-cmd): switching target and building in one batch run fails while a domain reload is pending. Modeled on the author's own `BuildAndroid.cs` (Arena Calibration System) |
| `build-patterns.txt` `CS` | C# errors that only the player build hits | Interview: Claude uses wrong or old Unity APIs. Roadmap PROD-53: C# in player-only code (`#if !UNITY_EDITOR`). Seen in the author's lasertag log: CS0246 and CS0305 in a failed Quest build |
| `build-patterns.txt` `SHADER` | `Shader error in '...' ... at File(line) (on api)` | The author's lasertag build log (`Issues/Netcode failure.log`): compute shader errors `(on vulkan)` in a failed Quest build |
| `build-patterns.txt` `IL2CPP` | Linker and IL2CPP failures | Unity issues on [UnityLinker.exe did not run properly](https://issuetracker.unity3d.com/issues/ios-unity-build-fails-unitylinker-dot-exe-did-not-run-properly) and [il2cpp build fails with specific dlls](https://issuetracker.unity3d.com/issues/il2cpp-build-fails-when-specific-dll-files-are-in-the-project) |
| `build-patterns.txt` `GRADLE`, `ANDROID-SDK` | Gradle failure and its "What went wrong" cause; SDK not found | Interview: Unity 6.3 Android SDK detection regression. Unity forum, [unable to locate Android SDK](https://forum.unity.com/threads/unable-to-locate-android-sdk.754667/) |
| `build-patterns.txt` `SCENE`, scene list check | Enabled scene missing, no enabled scenes, scene loaded by name but not enabled | Unity issues [UUM-1205](https://issuetracker.unity3d.com/product/unity/issues/guid/UUM-1205) and [empty scene entries](https://issuetracker-mig.prd.it.unity3d.com/issues/scene-thats-enabled-equals-true-in-projectsettings-slash-editorbuildsettings-with-empty-guid-and-path-fields-results-in-build-errors) ("is an incorrect path for a scene file"); the author's `BuildAndroid.cs` refuses to build with no enabled scenes |
| `build-patterns.txt` `BUILD`, build size | `Build Finished, Result: Failure.`/`Success.`, `Complete build size` | The author's build logs: Arena Calibration System `Logs/apk*.log` (success, size) and lasertag (failure). `MODULE`: Unity forum, [build target was unsupported](https://discussions.unity.com/t/error-building-player-because-build-target-was-unsupported-719893/719893) |
| `compile-fix` skill | Use APIs that exist in the project's Unity version | Interview: Claude uses wrong or old Unity APIs |
| `precommit` skill | Zero errors, no new warnings, `.meta` pairs, no broken references, tests pass | Interview: pre-commit checklist |
| `init` skill, template | Record the domain reload state | Interview: domain reload depends on the project |
| `unity-reviewer` check 1, template rule 6 | Reset static state | Interview: static state leaks with domain reload off; reload is turned off only once statics are reset |
| `unity-reviewer` check 2, template rules 3-4 | `.meta`/GUID safety | Interview |
| `unity-reviewer` check 3, template rule 2 | Unity version APIs | Interview |
| `unity-reviewer` check 4, template rule 1 | Match the project's namespaces, asmdefs and patterns | Interview: the instruction given to Claude most often |
| `perf-reviewer` checks 1-3 | GC allocations, batching, Update/physics cost | Interview: the checks wanted in a perf review |
| `docs/ROADMAP.md` Quest items | Android SDK detection, OpenXR package conflict | Issues the author hit in production |

## Deliberately not included

| Left out | Why |
|---|---|
| Test-run skill | Covered by `unity test` (Unity's plugin) and the Unity-Skills `test` module; `precommit` calls them |
| Render pipeline skill | Covered by Unity's official plugin (URP skills) |
| Perf checklist skill | Covered by Unity-Skills profiler/optimization modules; the perf rules live in `perf-reviewer` |
| Blocking scene/prefab edits | Not something the author asked to block |
