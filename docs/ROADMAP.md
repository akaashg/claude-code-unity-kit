# Roadmap

## Core (`unity-kit`)

- Verify the Unity-Skills and Unity CLI compile routes against a running Editor (see [TESTED.md](TESTED.md)).
- Run the kit on macOS against a real Unity install.
- Support Windows machines without Git Bash (PowerShell versions of the hook scripts).
- Skip the Stop-hook compile when `compile-fix` just compiled clean in the same turn.
- Find out why a hook-driven batch run adds `com.unity.toolchain.win-x86_64-linux-x86_64` to `manifest.json` (see [TESTED.md](TESTED.md)).
- Run the `precommit-trigger` eval on macOS or Linux.

## Packs

Each pack is a separate plugin that depends on `unity-kit`. See [PACKS.md](PACKS.md) for how to build one. Items below are issues the author has hit in production; a pack gets built when it has enough of them.

### `unity-kit-quest` (Meta Quest)

- **Unity version for Quest builds.** Unity 6.3 has an Android SDK detection regression; Quest apps are built on Unity 6.0. The pack should check the project's Unity version and warn before an Android build on an affected version.
- **OpenXR package conflict.** `com.unity.xr.androidxr-openxr` conflicts with Meta's OpenXR package. The pack should flag a manifest that contains both.

### `unity-kit-openxr`

No items yet.

### `unity-kit-mobile`

No items yet.

### Candidates (not confirmed)

- Networking (Photon Fusion): the author uses it; no rules collected yet.
