---
name: precommit
description: Pre-commit check for a Unity project - zero compile errors, no new compiler warnings, every asset has its .meta, tests pass. Use when the user is about to commit, asks if changes are ready to commit or push, or asks for a pre-commit check in a Unity project.
---

# Unity pre-commit check

Run all four checks, then report. Run scripts with the Bash tool.

1. **Compiles with zero errors.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/compile-check.sh" --state "${CLAUDE_PLUGIN_DATA}"`. Exit 0 is a pass. Exit 1 is a fail: list the errors. Exit 3 means the result is stale or no route was available: report it as **not checked** and give the reason the script printed.
2. **No new warnings.** From the same report, take the `warning CS` lines whose file is in `git diff --name-only HEAD` or `git ls-files --others --exclude-standard`. Any such line is a fail. Warnings in files this change did not touch are not new; mention their count only.
3. **Every asset has its `.meta`.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/meta-check.sh"`. Exit 0 is a pass; otherwise list what it printed.
4. **Tests pass.** Find test assemblies: asmdefs under `Assets/` that reference `UnityEngine.TestRunner` or list `UNITY_INCLUDE_TESTS` in `defineConstraints`. If there are none, report **no tests** (not a pass). Otherwise run them through what is available, in this order:
   - Unity-Skills `test` module, if its server answers on localhost 8090-8100.
   - `unity test` (Unity CLI). It runs in batch mode, so it cannot run while the Editor has the project open; if it is open, report **not checked** and say why.

## Report

A four-row table: check, result (pass / fail / not checked / no tests), detail. Then one line: **ready to commit** only if every row is pass (or no tests). Never call a change ready when a check was not run.
