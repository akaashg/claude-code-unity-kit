---
name: precommit
description: Pre-commit check for a Unity project - zero compile errors, no new compiler warnings, every asset has its .meta, no broken asset references, Unity's repository and project integrity checks, tests pass. Use when the user is about to commit, asks if changes are ready to commit or push, or asks for a pre-commit check in a Unity project.
---

# Unity pre-commit check

Run all six checks, then report. Run the scripts with the Bash tool, exactly as written and each on its own (no `; echo`, pipes or `&&`); each one's last line states the result.

1. **Compiles with zero errors.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/compile-check.sh" --state "${CLAUDE_PLUGIN_DATA}"`. Exit 0 is a pass. Exit 1 is a fail: list the errors. Exit 3 means the result is stale or no route was available: report it as **not checked** and give the reason the script printed.
2. **No new warnings.** From the same report, take the `warning CS` lines whose file is in `git diff --name-only HEAD` or `git ls-files --others --exclude-standard`. Any such line is a fail. Warnings in files this change did not touch are not new; mention their count only.
3. **Every asset has its `.meta`.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/meta-check.sh"`. Exit 0 is a pass; otherwise list what it printed.
4. **No broken asset references.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/ref-check.sh" --state "${CLAUDE_PLUGIN_DATA}"`. Exit 0 is a pass; mention any references it lists as already in the last commit. Exit 1 is a fail: list each broken reference. Exit 2 is **not checked**: give the reason it printed.
5. **Unity's integrity checks.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/unity-verify.sh"` with `run_in_background`, since `unity projects verify` can take a minute on a large project, and wait for it. It runs `unity projects verify` and `unity vcs doctor`, read-only. Exit 0 is a pass; mention the errors it lists as already in the repository and the warnings, briefly. Exit 1 is a fail: list each error in a touched file. Exit 4 is **not installed** (the Unity CLI isn't on this machine): not a fail. Exit 3 is **not checked**: give the reason it printed. For findings marked fixable, suggest `unity vcs doctor --fix` to the user; never run it yourself.
6. **Tests pass.** Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/test-check.sh"` with `run_in_background`, since Unity can take minutes, and wait for it. Exit 0 is a pass. Exit 1 is a fail: list each `FAIL` line, or the compile errors that stopped the run. Exit 4 is **no tests** (not a pass): there is no test assembly, or it has no tests. Exit 3 is **not checked**: give the reason it printed (for example, the Editor has the project open and no Unity-Skills server answers).

## Report

A six-row table: check, result (pass / fail / not checked / not installed / no tests), detail. Then one line: **ready to commit** only if every row is pass (or no tests, or not installed for the Unity CLI row). Never call a change ready when a check was not run.
