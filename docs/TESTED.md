# What was tested

Only what was actually run is listed. "Not verified" means exactly that.

## Environment

| | Version |
|---|---|
| Claude Code | 2.1.286 (validate, hook tests); 2.1.300 (headless `claude -p` runs and evals) |
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
| Hook scripts (`tests/hooks.test.sh`) | Works | 18/18 on Windows (Git Bash), including a non-ASCII project path |
| Install from the local marketplace | Works | `claude plugin details unity-kit` lists 3 skills, 2 agents, 2 hooks; about 405 always-on tokens |
| `guard-paths` hook in a live session | Works | From the installed plugin, Claude Code blocked an Edit to `Assets/Scripts.meta` and a Write under `Library/` in the sandbox, with the hook's message shown to Claude |
| Eval suite (`plugins/unity-kit/evals`) | Loads; did not run | All three cases load. Run from PowerShell, every fixture script failed before Claude started: `bash` resolved to WSL's `bash.exe` with no distro installed. $0 spent. Needs a re-run from Git Bash. On Windows, Claude Code also refuses a Bash grant because it can't sandbox the shell, so `precommit-trigger` has to run on macOS or Linux |
| `/unity-kit:init` (headless, `claude -p`) | **Failed, fixed, not re-run** | It read all five project facts correctly (6000.0.84f1, URP 17.0.4, domain reload off, no asmdefs) but wrote no `CLAUDE.md`: reading the template from the plugin folder was denied, because a headless run can't ask for permission outside the project. The template is now inline in the skill |
| Demo task (headless, with the kit, before `CLAUDE.md` existed) | Correct result, not credited to the kit | Claude added `Health.cs` with a `SubsystemRegistration` reset and moved `Readme.cs` with `git mv` for both the script and its `.meta`. It read the domain reload setting itself. With no `CLAUDE.md` loaded, this shows what Claude did, not what the kit's rules did |
| Stop hook in a real session | Works | Ran after each headless turn: 75 s on the first batch compile, 33 s on the second. Compiled clean. It first reported `Health.cs` as missing its `.meta`, because it checked `.meta` files before batch mode imported the script. Now it compiles first; re-checked on the sandbox with a new script: Unity wrote the `.meta`, no message, 34 s |
| Batch-mode side effect | Observed | The first hook-driven batch run added `com.unity.toolchain.win-x86_64-linux-x86_64` to the sandbox's `Packages/manifest.json` (timestamp inside the hook's run). Earlier manual batch runs did not. Cause not identified |
| `compile-check.sh` Unity-Skills route | Not verified | Needs a running Unity-Skills server |
| `compile-check.sh` Unity CLI route | Not verified | Needs the Pipeline package and a connected Editor; command names come from the Unity CLI docs |
| `compile-check.sh` Editor.log route with the Editor open | Not verified | |
| Lock-file detection with the Editor open | Not verified | |
| macOS | Not verified | Hook tests are set up to run on macOS in CI |
| Windows without Git Bash | Not supported | |
