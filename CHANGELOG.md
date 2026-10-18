# Changelog

## 0.2.0 (2026-10-18)

- **Broken asset references block the end of a turn.** New `ref-check.sh` finds GUIDs referenced from scenes, prefabs, materials and other text assets, and from asmdefs, that no `.meta` has. It blocks when the reference broke since the last commit: the asset was deleted, or moved without its `.meta`, or a GUID was written by hand. References already broken in the last commit, and unknown GUIDs in asmdefs, are reported by `precommit` and don't block. Runs in the Stop hook and as a fifth `precommit` check. Tested read-only on three real projects: no false positives, 2.6-4.6 s.
- **Player build check and `/unity-kit:build-fix`.** New `build-check.sh` builds a player for one target through the Unity CLI or batch mode, and reports C# errors in player-only code, shader errors, IL2CPP and stripping errors, Gradle and Android SDK errors, and missing scenes in the build list, as `File(line,col): error CLASS: ...` lines. Patterns are in one file, `build-patterns.txt`. It prints the build size and the change since the last build. Targets without a batch build flag (Android, iOS, WebGL) use a build profile, the project's build method, or a small `Assets/Editor/UnityKitBuild.cs` the skill offers to add. User-triggered only. Tested with a fake Unity and with real Windows and Android builds of the sandbox (Unity 6000.0.84f1).
- **Test run check and `/unity-kit:test-fix`.** New `test-check.sh` runs EditMode and PlayMode tests through the Unity-Skills `test` module, the Unity CLI (`unity test`) or batch mode (`-runTests`), and reads Unity's NUnit results XML into one line per failure: `FAIL <test> | <message> | Assets/...cs:line`. It reports compile errors that stopped the run, and **no tests** when the project has no test assembly. `test-fix` fixes the code under test, not the test, and asks before changing a test that is clearly wrong. User-triggered only. `precommit` now runs `test-check.sh` for its "tests pass" check. Tested with a fake Unity and a fake Unity-Skills server, and with real EditMode runs of the sandbox (Unity 6000.0.84f1) through batch mode and the Unity CLI; the Unity-Skills route was not run against a real server.
- New eval case `deleted-asset-blocked`.

## 0.1.2 (2026-10-15)

- **No second compile at the end of a turn.** When `compile-fix` or `precommit` just compiled clean and no script changed since, the Stop hook skips its compile (16.5 s to 0.9 s in testing). A result with errors is never skipped.
- `compile-fix` and `precommit` tell Claude to run `compile-check.sh` exactly as written, so it doesn't append `; echo` and get the command refused in headless runs.

## 0.1.1 (2026-10-15)

Fixes found by running the kit against a real Unity 6000.0.84f1 Editor. Details in [docs/TESTED.md](docs/TESTED.md).

- **Fresh clones no longer block the first turn.** Git doesn't keep empty folders, so a cloned project could have a folder's `.meta` without the folder, and the Stop hook treated it as an orphan. It's now a non-blocking note; Unity recreates the folder on import.
- **Unity CLI compile route works.** It now uses `recompile` and `recompile_status` from Unity's Pipeline package, which force a compile even while Unity is in the background and return the errors directly.
- **`Editor.log` route matches Git Bash paths.** Called with `/e/...`, the check wrongly said the log belonged to another Editor.
- **`unity-reviewer` picks up review requests.** Asking Claude to review Unity C# now goes to the agent (3/3 eval runs, was 0/2).
- Compile errors from every route are printed the same way: `File.cs(line,col): error CSxxxx: message`.

## 0.1.0 (2026-10-15)

First release: `.meta`/`Library`/`Temp` guard, Stop-time `.meta` and compile checks, `init`, `compile-fix` and `precommit` skills, `unity-reviewer` and `perf-reviewer` agents.
