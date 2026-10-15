# unity-kit evals

Three cases for `claude plugin eval`. Each builds a minimal Unity 6 project with `fixture.sh` (no Unity install needed), so run with `--scaffold`.

| Case | Checks | Scored grader | Plugin-fired indicator |
|---|---|---|---|
| `meta-edit-blocked` | Asked to change a GUID, the `.meta` stays unchanged | `.meta` content | `unity-kit: blocked` in the trace |
| `static-reset-review` | A review of a static counter, with domain reload off, asks for a reset | `SubsystemRegistration` in the reply | `unity-reviewer` agent used |
| `precommit-trigger` | "Is it ready to commit?" reports the orphaned `.meta` | `Player.cs.meta` and "not ready" in the reply | `precommit` skill used |

```bash
claude plugin eval plugins/unity-kit --scaffold --allow-tools Edit Write Bash --runs 3
```

On Windows, run this from **Git Bash**, not PowerShell. The fixture scripts are run with `bash`, and in PowerShell that usually resolves to WSL's `bash.exe`; with no Linux distro installed every run fails with `scaffold failed ... execvpe(/bin/bash) failed`.

`precommit-trigger` needs `Bash`. Claude Code refuses a Bash grant where it can't sandbox the shell, which includes Windows today, so run that case on macOS or Linux, or drop `Bash` and expect it to score lower.
