# Platform rules instead of packs

An earlier plan split platform knowledge into separate plugins (`unity-kit-quest`, `unity-kit-openxr`, `unity-kit-mobile`). That plan is dropped. A Quest project and an Android XR project hit mostly the same pipeline problems: compile errors, broken `.meta` files and references, failed builds, failing tests. What differs between platforms is mostly data: which Unity versions, packages and build targets cause trouble. So:

- **Pipeline stages** (compile, references, build, tests, ...) are scripts, hooks and skills in the one `unity-kit` plugin. See [ROADMAP.md](ROADMAP.md).
- **Platform, SDK and package problems** will be rule files inside `unity-kit`, checked by a project rules check. That check is built but not released yet; it is planned for 0.3.0.

| Goes in a stage (script, gate, skill) | Goes in a rule |
|---|---|
| Applies to any Unity 6 project | Applies only to some Unity versions, packages or build targets |
| `.meta` safety, compile gate, broken references, build errors, test failures | Unity 6.3 Android SDK detection, OpenXR package conflicts |
| Needs code to detect | Can be stated as "this version, these packages, this target" |

## Proposing a rule

Until the project rules check is released, open a [Rule proposal](../.github/ISSUE_TEMPLATE/rule_proposal.yml) issue with the problem and where it comes from: the real problem you hit, a Unity issue tracker link, or a Unity doc page. Rules from general best-practice lists aren't added. Each accepted rule gets a row in [SOURCES.md](SOURCES.md) and an entry under "Planned rules" in [ROADMAP.md](ROADMAP.md).

## Adding a stage

Follow `compile-check.sh`, `ref-check.sh`, `build-check.sh` and `test-check.sh`:

1. **A detect script** in `plugins/unity-kit/scripts/`: POSIX `sh` that runs on macOS `sh` and Git Bash on Windows, without jq, Node or Python. It prints problems as file and line and exits 0 (clean), 1 (errors) or 3 (not checked), saying why when it couldn't check.
2. **A gate**, only if the check is fast: a step in `stop-checks.sh` or a row in the `precommit` skill. Slow checks such as builds are started by the user.
3. **A fix-loop skill**, when Claude can fix the problem itself: run the script, fix, run it again, at most 5 rounds.
4. **Tests** in `tests/hooks.test.sh` with a fake project (and a fake Unity where the script launches one), a row in [SOURCES.md](SOURCES.md), a "How the ... check works" section in the README, and a row in [TESTED.md](TESTED.md) that lists only what was actually run.
