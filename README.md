# claude-code-unity-kit

<!-- GIF placeholder: docs/media/demo.gif (see docs/DEMO.md for the storyboard) -->
![unity-kit demo](docs/media/demo.gif)

A [Claude Code](https://code.claude.com) plugin for Unity 6 projects. It stops the mistakes Claude makes most often in Unity and won't let a turn end with a broken project.

## What it fixes

| Without the kit | With `unity-kit` |
|---|---|
| Claude edits or invents `.meta` files and GUIDs break | Edits to `.meta` files are blocked |
| An asset moved in the shell leaves its `.meta` behind, and references go missing | The turn can't end while an orphaned `.meta` exists |
| An asset that only a scene or prefab uses (by GUID) gets deleted as "unused", or Claude writes a GUID by hand | The turn can't end while a reference broke since the last commit |
| Claude says "done" while the Console is red | The turn can't end while the project has compile errors |
| Static fields keep their values between Play sessions when domain reload is off | `CLAUDE.md` records the domain reload state and requires a reset; `unity-reviewer` checks it in reviews |
| Code written for a different Unity version | The project's Unity version is in `CLAUDE.md` and checked in review |
| New code ignores the project's namespaces and asmdefs | Matching the project's style is rule 1 |

## Install

```bash
claude plugin marketplace add akaashg/claude-code-unity-kit
claude plugin install unity-kit@akaashg-unity
```

Then, in your Unity project, run `/unity-kit:init` once.

**Requirements:** Claude Code (tested on 2.1.286), Unity 6. On Windows the hooks need Git Bash (Git for Windows); macOS uses the built-in `sh`.

## Contents

| Type | Name | What it does |
|---|---|---|
| Skill | `/unity-kit:init` | Writes a `CLAUDE.md` with the project's Unity version, render pipeline, domain reload state and asmdefs |
| Skill | `/unity-kit:build-fix` | Build a player for one target, fix, rebuild until it builds (max 5 rounds). Run it yourself: builds take minutes |
| Skill | `compile-fix` | Compile, fix, recompile until clean (max 5 rounds) |
| Skill | `precommit` | Zero errors, no new warnings, every asset has its `.meta`, no broken references, tests pass |
| Hook | `guard-paths` | Blocks writes to `.meta` files, `Library/` and `Temp/` |
| Hook | `stop-checks` | At end of turn: `.meta` pairing, broken asset references, and a compile check when scripts changed |
| Agent | `unity-reviewer` | Static reset, `.meta`/GUID safety, Unity version APIs, project style. Picks up review requests for Unity C# |
| Agent | `perf-reviewer` | Per-frame GC allocations, SRP Batcher/instancing breakers, Update/physics cost |

Why each rule exists: [docs/SOURCES.md](docs/SOURCES.md). What was tested: [docs/TESTED.md](docs/TESTED.md).

## How the reference check works

`ref-check.sh` reads every GUID that a scene, prefab, material or other text asset references, and every `GUID:` in an asmdef, and looks for a `.meta` with that GUID in `Assets/`, `Packages/`, local `file:` packages and `Library/PackageCache`. GUIDs of Unity's built-in resources are skipped.

It blocks only on references that broke since the last commit: the GUID was in a `.meta` at `HEAD` (the asset was deleted, or moved without its `.meta`), or a changed file references a GUID that no asset or package has and that the file didn't reference at `HEAD`. Broken references already committed are listed by `precommit` but don't block, so an older project with Missing references doesn't stop every turn. An unknown GUID in an asmdef doesn't block either: Asset Store asmdefs often reference optional assemblies that aren't installed. Without git, or without `Library/PackageCache` (a clone never opened in Unity), it reports what it couldn't resolve and doesn't block.

In a git repo it reads files with `git grep`, which is several times faster than `find` on Windows: about 5 s on a project with 3,000 scenes, prefabs and materials and 80 packages. See [docs/TESTED.md](docs/TESTED.md).

**Not checked:** binary-serialized assets (Asset Serialization other than Force Text), and GUIDs in UXML, USS and Shader Graph files.

## How the compile check works

Unity can't open a project in batch mode while the Editor has it open, so the check picks the first route that works:

1. **[Unity-Skills](https://github.com/Besty0728/Unity-Skills)** server, if running: reads the last compile result, and reports **stale** if scripts changed after it.
2. **Unity CLI** with a connected Editor (needs Unity's `com.unity.pipeline` package): triggers a recompile, which works while Unity is in the background, and reads the result.
3. **`Editor.log`** of the Editor that has the project open, with the same staleness check.
4. **Batch mode**, when the Editor is closed. Off by default for the end-of-turn hook (`batch_compile` option); `compile-fix` always allows it.

**Unity 6.0 note:** if the Editor install has Linux Dedicated Server Build Support, any Unity launch, including the batch compile, adds `com.unity.toolchain.win-x86_64-linux-x86_64` to `Packages/manifest.json`. That's Unity bug [UUM-75804](https://issuetracker.unity.com/issues/15311/toolchain-win-linux-x64-package-is-always-automatically-installed-when-the-used-editor-installation-has-the-linux-dedicated-server-support-component) (won't fix in 6.0, fixed in 6.1+), not the kit. To stop it on your machine: Edit → Project Settings → Toolchain Management, turn off "Install Toolchain package automatically", then remove the package. In testing this held across an Editor restart, but the setting isn't saved in any file under version control.

**Limitation:** Unity only recompiles when the Editor window gets focus, unless something forces it. With the Editor open, only the Unity CLI route forces a recompile; the Unity-Skills and `Editor.log` routes report **stale** instead of guessing when scripts changed after the last compile.

## How the build check works

A project can compile in the Editor and still fail to build: code under `#if !UNITY_EDITOR`, shaders for the target's graphics API, IL2CPP stripping, Gradle. `/unity-kit:build-fix Android` (or `StandaloneWindows64`, `iOS`, `WebGL`, or a build profile name) runs `build-check.sh`, fixes what it reports and builds again. It never runs on its own: not at the end of a turn, not in `precommit`.

1. **Scene list first.** An enabled scene in `ProjectSettings/EditorBuildSettings.asset` whose file is gone, or no enabled scene at all, stops it before Unity starts. A scene loaded by name with `SceneManager.LoadScene("...")` that isn't enabled in the list is a warning.
2. **Unity CLI** `unity build`, if installed, else **batch mode**. Both need the Editor closed; with the project open in the Editor the result is **not checked**.
3. **How Unity builds the target.** Desktop targets use Unity's `-buildWindows64Player`-style flags. A Unity 6 build profile uses `-activeBuildProfile` and `-build`. Other targets (Android, iOS, WebGL) have no batch build flag, so they need a profile, the project's own build method (`--method`), or `Assets/Editor/UnityKitBuild.cs`. The skill asks before adding that file, and never writes its `.meta`.
4. **The log.** Error lines are matched against [build-patterns.txt](plugins/unity-kit/scripts/build-patterns.txt), one regex per line, by class: `CS`, `SHADER`, `IL2CPP`, `GRADLE`, `ANDROID-SDK`, `SCENE`, and generic `MODULE`/`BUILD`. To catch a new failure, add a line there. The full log stays in `Logs/unity-kit-build-<target>.log`; the player goes to `Builds/unity-kit/<target>/` unless you pass `--output`.
5. **Size.** After a successful build it prints Unity's "Complete build size" and the change since the last build of that target.

Exit codes match the compile check: 0 built, 1 build errors, 3 not checked.

## Works alongside

unity-kit adds guardrails and workflow; it doesn't drive the Editor. It's designed to run next to:

- [Unity's official Claude Code plugin](https://github.com/Unity-Technologies/unity-agent-plugin) (Unity CLI, UI, 2D, URP and more)
- [Unity-Skills](https://github.com/Besty0728/Unity-Skills) and other Unity MCP servers

## Packs coming

Platform-specific rules ship as separate plugins that depend on `unity-kit`: `unity-kit-quest`, `unity-kit-openxr`, `unity-kit-mobile`. See [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/PACKS.md](docs/PACKS.md).

## License

[MIT](LICENSE) © 2026 Akaash Garg
