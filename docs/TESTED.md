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
| Install from GitHub (README commands) | Works | In a clean, separate config (`CLAUDE_CONFIG_DIR`): `claude plugin marketplace add akaashg/claude-code-unity-kit` then `claude plugin install unity-kit@akaashg-unity`. Installed 0.1.0 from `main` into the plugin cache; 3 skills, 2 agents, 2 hooks. From the cached copy, the guard blocked a `.meta` edit and the Stop hook compiled a fresh clone of the sandbox clean in 107 s (cold, no `Library/`) |
| `meta-check.sh` on a fresh git clone | Fixed | Git does not keep empty folders, so the clone had `Assets/Scripts.meta` without the folder, and the check called it an orphan. With batch compile off (the default) that would have blocked the first turn. Folder `.meta` files with a missing folder are now a non-blocking note; Unity recreated the folder on import |
| `guard-paths` hook in a live session | Works | From the installed plugin, Claude Code blocked an Edit to `Assets/Scripts.meta` and a Write under `Library/` in the sandbox, with the hook's message shown to Claude |
| Eval: `meta-edit-blocked` | Works, Δ +1.0 | With the kit 2/2 (`.meta` unchanged, hook message in the trace); without it 0/2 (Claude changed the GUID as asked). 2 runs per arm, Git Bash, $0.33 |
| Eval: `static-reset-review` | Works after a fix; Δ 0 on the answer | First version of the agent description: 0/2 runs delegated to `unity-reviewer` (Claude reviewed the file itself). After rewriting the description to lead with "Use for every review of Unity C# code": 3/3 runs delegated to `unity-kit:unity-reviewer`, which read the domain reload setting and asked for a `SubsystemRegistration` reset ($0.54, with-kit arm only). Claude without the kit also asks for the reset (2/2 earlier), so this case shows the reviewer fires, not that the answer improves |
| Eval: `precommit-trigger` | Not run | Needs a Bash grant, which Claude Code refuses on Windows without a shell sandbox; run on macOS or Linux. A first attempt from PowerShell failed before Claude started (`bash` resolved to WSL with no distro) |
| `/unity-kit:init` (headless, `claude -p`) | Works after a fix | First run read all five facts but wrote nothing: reading the template from the plugin folder was denied in a headless run. With the template inline in the skill, the re-run wrote `CLAUDE.md` with correct facts (6000.0.84f1, URP 17.0.4, domain reload off, no asmdefs): [examples/CLAUDE.md](../examples/CLAUDE.md) |
| Demo task (headless, with the kit and `CLAUDE.md`) | Works | Claude moved `Readme.cs` and its `.meta` with `git mv`, added a `SubsystemRegistration` reset citing the project rules, and called the `compile-fix` skill on its own ("Per project rule 7"); batch compile clean in about 31 s. An earlier run without `CLAUDE.md` also got the code right, so the kit's measurable effect here is the compile check, not the code |
| Redundant compile after `compile-fix` | Fixed | `compile-fix` and `precommit` now pass the plugin data folder to `compile-check.sh`, which records a clean result there; the Stop hook skips the compile when no script changed after it. A result with errors clears the record, so errors always block. Same headless task in the sandbox (Editor open, Unity CLI route): Stop hook 16.5 s before, 0.9 s after. Hook tests cover it with a fake Unity |
| Skills say to run `compile-check.sh` exactly as written | Not verified | In headless runs Claude first appended `; echo "EXIT=$?"`, which `claude -p` refuses as a multi-part command, then retried; both skills now say to run it on its own. The check run failed before Claude started because the CLI login had expired |
| Stop hook in a real session | Works | Ran after each headless turn: 75 s on the first batch compile, 33 s on the second. Compiled clean. It first reported `Health.cs` as missing its `.meta`, because it checked `.meta` files before batch mode imported the script. Now it compiles first; re-checked on the sandbox with a new script: Unity wrote the `.meta`, no message, 34 s |
| `com.unity.toolchain.win-x86_64-linux-x86_64` added to `manifest.json` | Explained: Unity bug | Not caused by the kit. Unity's package manager log shows the Editor itself requesting `project:add-dependency` for it about a second after startup, in batch mode and in the GUI alike. It started right after Linux Dedicated Server Build Support was installed for 6000.0.84f1 (23:54 on day 1); no Unity launch before that added it, every launch after did. This is Unity bug [UUM-75804](https://issuetracker.unity.com/issues/15311/toolchain-win-linux-x64-package-is-always-automatically-installed-when-the-used-editor-installation-has-the-linux-dedicated-server-support-component): "Won't Fix" for 6.0.X, fixed in 6.1 and later. The kit's batch compile is just one of the Unity launches that trigger it |
| `compile-check.sh` Unity-Skills route | Works | Unity-Skills 2.9.0 in the sandbox, server on, `auto` mode (the read-only check needs no grant). Clean project: "compiles clean via Unity-Skills" in about 1 s. After adding a broken script with Unity in the background, the server still reported the previous compile as succeeded; the script reported **STALE** (exit 3) instead of clean. After focusing Unity: the CS0103 error with file and line (exit 1) |
| `compile-check.sh` Editor.log route with the Editor open | Works | Sandbox open in the Editor with no errors: "compiles clean via Editor.log" (exit 0, about 14 s). After touching `Health.cs`: "STALE ... Focus the Unity Editor" (exit 3). Found and fixed a bug: called with a Git Bash path (`/e/...`), it wrongly said the log belonged to another Editor; paths are now converted to `E:/...` first |
| Lock-file detection with the Editor open | Works | With the Editor open, `Temp/UnityLockfile` was held and the script treated the project as open |
| `compile-check.sh` Unity CLI route | Works after a fix | `com.unity.pipeline` 0.8.0-exp.1 (experimental), Unity-Skills server off, Unity in the background. The first version polled for "completed" and read Editor.log; the real commands are `recompile` (works unfocused) and `recompile_status`, which returns the errors, so the route now uses those. With a new error added while unfocused: caught CS0029 with file and line, no click needed (exit 1, 16 s). After removing it: clean (exit 0, 20 s) |
| macOS | Hook scripts only | `tests/hooks.test.sh` and frontmatter checks pass on `macos-latest` in GitHub Actions. Not run against a real Unity install on macOS |
| CI | Works | First run on GitHub Actions: lint, `claude plugin validate --strict` (2.1.286 from npm), and hook tests on Ubuntu, macOS and Windows all passed |
| Windows without Git Bash | Not supported | |
