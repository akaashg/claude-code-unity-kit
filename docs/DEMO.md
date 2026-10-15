# Demo storyboard

One small task, done twice in the same project: once with plain Claude Code, once with `unity-kit`. Record both at 1280×720 and cut a 20–30 s GIF of the second run for the README (`docs/media/demo.gif`).

## Setup

1. Create a project from the **Universal 3D** template on Unity 6000.0.84f1 (`unity projects create UnityKitSandbox --editor-version 6000.0.84f1 --template com.unity.template.urp-blank`).
2. In **Project Settings > Editor > Enter Play Mode Settings**, turn domain reload off.
3. `git init` the project with a Unity `.gitignore` and commit, so both runs start from the same state.
4. Close the Editor for run A and run B, so batch mode can run.

## The task (same prompt both runs)

> Add a `Health` MonoBehaviour in `Assets/Scripts/Health.cs` with a static `AliveCount` that goes up in `OnEnable` and down in `OnDisable`. Then move `Assets/TutorialInfo/Scripts/Readme.cs` into `Assets/Scripts/`.

This one prompt exercises three things the kit should catch:

| Trap | What goes wrong without the kit |
|---|---|
| `static int AliveCount` with domain reload off | The count carries over between Play sessions |
| Moving `Readme.cs` with `mv` | `Readme.cs.meta` stays behind; the `Readme` asset loses its script reference |
| Any compile error in `Health.cs` | Claude ends the turn anyway |

## Run A: without the kit

1. `git reset --hard && git clean -fd`, then start `claude` in the project with no plugin.
2. Paste the prompt.
3. Show `git status`: `Readme.cs.meta` left in `Assets/TutorialInfo/Scripts/`, `Readme.cs` in `Assets/Scripts/` with no `.meta`.
4. Show `Health.cs`: no static reset.
5. Open the Editor: the Readme asset shows a missing script.

## Run B: with the kit

1. `git reset --hard && git clean -fd`, then start `claude --plugin-dir <repo>/plugins/unity-kit` (or with the installed plugin) and run `/unity-kit:init`. Show the generated `CLAUDE.md` with `domain reload off`.
2. Paste the same prompt.
3. Expected: Claude moves the `.meta` with the script (rule 4 in `CLAUDE.md`). If it doesn't, the Stop hook blocks the turn with `.meta files with no asset` and Claude moves it.
4. Expected: `Health.cs` has a `SubsystemRegistration` reset for `AliveCount` (rule 6).
5. Ask: "Use the unity-reviewer agent on this change." Show its report.
6. Run `/unity-kit:precommit` and show the four-row table.
7. Open the Editor: no missing script, the Console is clean.

## What to show in the GIF

Run B, steps 2–3 (the Stop hook output if it fires) and step 6 (the precommit table). Caption: "Same prompt. The kit keeps the .meta, resets the static, and won't finish on a broken compile."

Record what actually happens. If a step in run B does not behave as expected, note it in [TESTED.md](TESTED.md) instead of editing the video.
