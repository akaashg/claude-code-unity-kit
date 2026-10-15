# What was tested

Only what was actually run is listed. "Not verified" means exactly that.

## Environment

| | Version |
|---|---|
| Claude Code | 2.1.286 |
| Unity | 6000.0.84f1, Universal 3D template (`com.unity.template.urp-blank`), URP 17.0.4 |
| OS | Windows 11 Pro, Git Bash (Git 2.55) |
| Unity CLI | 1.0.0-beta.12 |

## Results

| Piece | Status | Notes |
|---|---|---|
| `claude plugin validate --strict` (plugin and marketplace) | Works | Passes on 2.1.286 |
| `compile-check.sh` batch route | Works | Deliberate CS0103 error: exit 1 with the error line. Fixed file: exit 0, CS0219 warning listed. About 5 s on the sandbox with a warm `Library/` |
| `compile-check.sh` lock-file detection | Works for a leftover lock | Unity left `Temp/UnityLockfile` behind after a batch run; the script correctly treated the project as closed |
| `meta-check.sh` | Works | Caught a script moved with `mv` (orphaned `.meta` + asset without `.meta`) in the sandbox |
| Hook scripts (`tests/hooks.test.sh`) | Works | 17/17 on Windows (Git Bash) |
| `compile-check.sh` Unity-Skills route | Not verified | Needs a running Unity-Skills server |
| `compile-check.sh` Unity CLI route | Not verified | Needs the Pipeline package and a connected Editor; command names come from the Unity CLI docs |
| `compile-check.sh` Editor.log route with the Editor open | Not verified | |
| Lock-file detection with the Editor open | Not verified | |
| macOS | Not verified | Hook tests are set up to run on macOS in CI |
| Windows without Git Bash | Not supported | |
