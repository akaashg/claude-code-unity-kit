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
| Version control | Large binaries outside Git LFS; scene and prefab merge conflicts | `precommit` | Skill that resolves scene conflicts with UnityYAMLMerge | Planned (0.3.0) |
| Import audit | Texture, audio and model import settings, read from `.meta` files | `precommit`, changed assets only | Skill that proposes the changes | Planned (0.3.0) |
| CI setup | None | None | `ci-init`: writes a GameCI workflow that runs the detect scripts, with build-size budgets | Planned (0.4.0) |
| Crash triage | `Player.log`, `Editor.log` and logcat captures | None | `triage`: maps crashes and exceptions back to project files | Planned (0.4.0) |

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
