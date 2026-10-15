# claude-code-unity-kit

<!-- GIF placeholder: docs/media/demo.gif (see docs/DEMO.md for the storyboard) -->
![unity-kit demo](docs/media/demo.gif)

A [Claude Code](https://code.claude.com) plugin for Unity 6 projects. It stops the mistakes Claude makes most often in Unity and won't let a turn end with a broken project.

## What it fixes

| Without the kit | With `unity-kit` |
|---|---|
| Claude edits or invents `.meta` files and GUIDs break | Edits to `.meta` files are blocked |
| An asset moved in the shell leaves its `.meta` behind, and references go missing | The turn can't end while an orphaned `.meta` exists |
| Claude says "done" while the Console is red | The turn can't end while the project has compile errors |
| Static fields keep their values between Play sessions when domain reload is off | `CLAUDE.md` records the domain reload state and requires a reset; `unity-reviewer` checks it when asked |
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
| Skill | `compile-fix` | Compile, fix, recompile until clean (max 5 rounds) |
| Skill | `precommit` | Zero errors, no new warnings, every asset has its `.meta`, tests pass |
| Hook | `guard-paths` | Blocks writes to `.meta` files, `Library/` and `Temp/` |
| Hook | `stop-checks` | At end of turn: `.meta` pairing, and a compile check when scripts changed |
| Agent | `unity-reviewer` | Static reset, `.meta`/GUID safety, Unity version APIs, project style. Ask for it by name; it did not trigger on its own in testing |
| Agent | `perf-reviewer` | Per-frame GC allocations, SRP Batcher/instancing breakers, Update/physics cost |

Why each rule exists: [docs/SOURCES.md](docs/SOURCES.md). What was tested: [docs/TESTED.md](docs/TESTED.md).

## How the compile check works

Unity can't open a project in batch mode while the Editor has it open, so the check picks the first route that works:

1. **[Unity-Skills](https://github.com/Besty0728/Unity-Skills)** server, if running: reads the last compile result, and reports **stale** if scripts changed after it.
2. **Unity CLI** with a connected Editor: triggers a recompile, then reads `Editor.log`.
3. **`Editor.log`** of the Editor that has the project open, with the same staleness check.
4. **Batch mode**, when the Editor is closed. Off by default for the end-of-turn hook (`batch_compile` option); `compile-fix` always allows it.

**Limitation:** with the Editor open and no Unity-Skills or Unity CLI connection, Unity only recompiles when the Editor window gets focus. The check then reports **stale** instead of guessing.

## Works alongside

unity-kit adds guardrails and workflow; it doesn't drive the Editor. It's designed to run next to:

- [Unity's official Claude Code plugin](https://github.com/Unity-Technologies/unity-agent-plugin) (Unity CLI, UI, 2D, URP and more)
- [Unity-Skills](https://github.com/Besty0728/Unity-Skills) and other Unity MCP servers

## Packs coming

Platform-specific rules ship as separate plugins that depend on `unity-kit`: `unity-kit-quest`, `unity-kit-openxr`, `unity-kit-mobile`. See [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/PACKS.md](docs/PACKS.md).

## License

[MIT](LICENSE) © 2026 Akaash Garg
