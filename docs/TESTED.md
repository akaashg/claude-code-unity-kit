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
| Eval: `meta-edit-blocked` | Works, Δ +1.0 | With the kit 2/2 (`.meta` unchanged, hook message in the trace); without it 0/2 (Claude changed the GUID as asked). 2 runs per arm, Git Bash, $0.33 |
| Eval: `static-reset-review` | Δ 0; reviewer did not fire | 2/2 with and 2/2 without: Claude asks for a `SubsystemRegistration` reset on its own. The `unity-reviewer` agent was not used in either with-kit run, so its "use proactively" description did not trigger delegation. $0.47 |
| Eval: `precommit-trigger` | Not run | Needs a Bash grant, which Claude Code refuses on Windows without a shell sandbox; run on macOS or Linux. A first attempt from PowerShell failed before Claude started (`bash` resolved to WSL with no distro) |
| `/unity-kit:init` (headless, `claude -p`) | Works after a fix | First run read all five facts but wrote nothing: reading the template from the plugin folder was denied in a headless run. With the template inline in the skill, the re-run wrote `CLAUDE.md` with correct facts (6000.0.84f1, URP 17.0.4, domain reload off, no asmdefs): [examples/CLAUDE.md](../examples/CLAUDE.md) |
| Demo task (headless, with the kit and `CLAUDE.md`) | Works | Claude moved `Readme.cs` and its `.meta` with `git mv`, added a `SubsystemRegistration` reset citing the project rules, and called the `compile-fix` skill on its own ("Per project rule 7"); batch compile clean in about 31 s. An earlier run without `CLAUDE.md` also got the code right, so the kit's measurable effect here is the compile check, not the code |
| Redundant compile | Known | After `compile-fix` compiled, the Stop hook compiled again (29 s), because it only trusts its own last-check time |
| Stop hook in a real session | Works | Ran after each headless turn: 75 s on the first batch compile, 33 s on the second. Compiled clean. It first reported `Health.cs` as missing its `.meta`, because it checked `.meta` files before batch mode imported the script. Now it compiles first; re-checked on the sandbox with a new script: Unity wrote the `.meta`, no message, 34 s |
| Batch-mode side effect | Observed twice | After a reset of the sandbox, the first hook-driven batch run added `com.unity.toolchain.win-x86_64-linux-x86_64` to `Packages/manifest.json` both times. Manual batch runs before that did not. Cause not identified |
| `compile-check.sh` Unity-Skills route | Not verified | Needs a running Unity-Skills server |
| `compile-check.sh` Unity CLI route | Not verified | Needs the Pipeline package and a connected Editor; command names come from the Unity CLI docs |
| `compile-check.sh` Editor.log route with the Editor open | Not verified | |
| Lock-file detection with the Editor open | Not verified | |
| macOS | Not verified | Hook tests are set up to run on macOS in CI |
| Windows without Git Bash | Not supported | |
