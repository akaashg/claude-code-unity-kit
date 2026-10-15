# Where each rule comes from

Every rule, hook, skill and agent check in unity-kit traces to the author's own Unity workflow, collected in an interview on 2026-10-14. Nothing here is copied from a client project. If a change adds a rule, add its source to this table.

| Piece | Rule or check | Source |
|---|---|---|
| `guard-paths` hook | Block edits to existing `.meta` files | Interview: the one file type Claude must never edit by hand |
| `guard-paths` hook | Block writing new `.meta` files | Interview: Claude breaks `.meta`/GUIDs when moving or renaming assets |
| `guard-paths` hook | Block edits under `Library/` and `Temp/` | Original brief for the kit |
| `stop-checks` hook, `meta-check.sh` | Orphaned `.meta` / asset without `.meta` | Interview: breaks `.meta`/GUIDs; pre-commit check "every asset has its .meta" |
| `stop-checks` hook, `compile-check.sh` | Compile gate at end of turn | Interview: pre-commit check "compiles with zero errors" |
| `compile-check.sh` routes | Unity-Skills, Unity CLI, Editor.log, batch mode | Interview: how compile errors reach Claude today |
| `compile-fix` skill | Use APIs that exist in the project's Unity version | Interview: Claude uses wrong or old Unity APIs |
| `precommit` skill | Zero errors, no new warnings, `.meta` pairs, tests pass | Interview: pre-commit checklist |
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
