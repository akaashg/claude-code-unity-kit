# Changelog

## Unreleased

- **No second compile at the end of a turn.** When `compile-fix` or `precommit` just compiled clean and no script changed since, the Stop hook skips its compile (16.5 s to 0.9 s in testing). A result with errors is never skipped.

## 0.1.1 (2026-10-15)

Fixes found by running the kit against a real Unity 6000.0.84f1 Editor. Details in [docs/TESTED.md](docs/TESTED.md).

- **Fresh clones no longer block the first turn.** Git doesn't keep empty folders, so a cloned project could have a folder's `.meta` without the folder, and the Stop hook treated it as an orphan. It's now a non-blocking note; Unity recreates the folder on import.
- **Unity CLI compile route works.** It now uses `recompile` and `recompile_status` from Unity's Pipeline package, which force a compile even while Unity is in the background and return the errors directly.
- **`Editor.log` route matches Git Bash paths.** Called with `/e/...`, the check wrongly said the log belonged to another Editor.
- **`unity-reviewer` picks up review requests.** Asking Claude to review Unity C# now goes to the agent (3/3 eval runs, was 0/2).
- Compile errors from every route are printed the same way: `File.cs(line,col): error CSxxxx: message`.

## 0.1.0 (2026-10-15)

First release: `.meta`/`Library`/`Temp` guard, Stop-time `.meta` and compile checks, `init`, `compile-fix` and `precommit` skills, `unity-reviewer` and `perf-reviewer` agents.
