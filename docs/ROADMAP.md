# Roadmap

unity-kit grows one production-pipeline stage at a time, not one device at a time. Each stage follows the same pattern:

- a **detect script**: POSIX `sh` that reads the project, reports problems as file and line, and exits with a plain code (0 clean, 1 errors, 3 not checked);
- a **gate**: the Stop hook or a `precommit` check that runs the script at the right moment, when the stage is fast enough to run there;
- a **fix-loop skill**: when Claude can fix the problem, a skill that runs the script, fixes, and runs it again, at most 5 rounds.

Platform, SDK and package problems don't get their own plugin. They are planned as rule files inside unity-kit; see [PACKS.md](PACKS.md).

## Stages

| Stage | Detect script | Gate | Fix-loop skill | Status |
|---|---|---|---|---|
| Compile | `compile-check.sh` | Stop hook, `precommit` | `compile-fix` | Released (0.1.0) |
| `.meta` pairing | `meta-check.sh` | Stop hook, `precommit` | None: Claude must not write `.meta` files | Released (0.1.0) |
| Asset references | `ref-check.sh` | Stop hook, `precommit` | None: restore the asset, or reassign the reference in the Editor | Released (0.2.0) |
| Build | `build-check.sh` | None: builds take minutes, so you start them | `build-fix` | Released (0.2.0) |
| Tests | `test-check.sh` | `precommit` | `test-fix` | Released (0.2.0) |
| Project rules | Unity version, packages and build target checked against rule files | `precommit`; Stop hook after a Unity version or package change | None: version and package changes are the user's call | Built on a branch, not merged (0.3.0) |
| Repository and project integrity | `unity-verify.sh`: Unity's own `unity projects verify` and `unity vcs doctor`, read-only | `precommit` | None: the kit suggests Unity's `unity vcs doctor --fix`, never runs it | Built, not released (0.3.0) |
| Team CI | The detect scripts, run on every PR against the PR base | GitHub Actions | `ci-init`: writes the workflow (no-Unity checks, tests and builds with a Unity license, optional reviewer comments) | Planned (0.3.0) |
| Quest device check | Frame time against the refresh-rate budget, and exceptions in logcat, through Meta's `hzos-dev-mcp` | None: needs a headset, so you start it | `device-check` | Planned (0.4.0) |
| Crash triage | `Player.log`, `Editor.log` and logcat captures | None | `triage`: groups crashes and exceptions and maps them back to project files | Planned (0.4.0) |

### Left to Unity's CLI

Unity's CLI (1.0.0-beta.13) already covers two stages that were planned here, so the kit calls it instead of rebuilding them:

- **Git LFS and ignore rules:** `unity vcs doctor` audits LFS patterns, ignore rules and package pinning, and repairs what it can with `--fix`. `unity-verify.sh` runs it from `precommit`.
- **Scene and prefab merges:** `unity vcs merge-setup` configures UnityYAMLMerge, and `unity vcs conflicts`, `explain` and `resolve` handle conflicted assets. `unity projects verify` catches leftover conflict markers; `ref-check.sh` still catches the broken references a merge can leave, which Unity's checks don't read.

**Deferred:** an import-settings audit. Unity's plugin already gives per-area advice (`optimize-audio`, `optimize-text-mesh-pro`, `manage-sprite-atlas`); a deterministic check is only worth building if that falls short.

The order above is the order of work. A stage is built when there is a real problem behind it; see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Planned rules

Platform problems the author has hit in production. They become rule files once the project rules check is released:

- **Unity version for Quest builds.** Unity 6.3 has an Android SDK detection regression; Quest apps are built on Unity 6.0. Warn before an Android build on an affected version.
- **OpenXR package conflict.** `com.unity.xr.androidxr-openxr` conflicts with Meta's OpenXR package. Flag a manifest that contains both. Which Meta package exactly is still to be confirmed.

Candidates (no rules collected yet):

- Networking (Photon Fusion): the author uses it.

## The kit itself

- Run the kit on macOS against a real Unity install.
- Support Windows machines without Git Bash (PowerShell versions of the hook scripts).
- Run the `precommit-trigger` and `deleted-asset-blocked` evals on macOS or Linux.
- `ref-check.sh`: also read GUIDs in UXML, USS and Shader Graph files, and time a cold run on a large project.
- `build-check.sh`: run real builds through a build profile, and for iOS, WebGL and macOS.
- `test-check.sh`: run real PlayMode tests, and the Unity-Skills route against a real server.
