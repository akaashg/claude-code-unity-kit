---
name: init
description: Set up a Unity project for Claude Code by writing a CLAUDE.md from the unity-kit template, filled with the project's Unity version, render pipeline, domain reload setting and assembly definitions. Run once per project.
argument-hint: "[path to Unity project, default: current directory]"
disable-model-invocation: true
---

# unity-kit init

Target project: `$ARGUMENTS` if given, otherwise the current directory. It must contain `ProjectSettings/ProjectVersion.txt`; if not, stop and say it is not a Unity project root.

## 1. Read the project facts

| Placeholder | How to read it |
|---|---|
| `{{UNITY_VERSION}}` | `m_EditorVersion:` in `ProjectSettings/ProjectVersion.txt` |
| `{{RENDER_PIPELINE}}` | `Packages/manifest.json`: `com.unity.render-pipelines.universal` → URP, `com.unity.render-pipelines.high-definition` → HDRP. If neither, and `m_CustomRenderPipeline` in `ProjectSettings/GraphicsSettings.asset` is `{fileID: 0}`, → Built-in. Add the package version. |
| `{{DOMAIN_RELOAD}}` | `ProjectSettings/EditorSettings.asset`: **off** only when `m_EnterPlayModeOptionsEnabled: 1` and `m_EnterPlayModeOptions` has bit 1 set (`DisableDomainReload`). Otherwise **on**. Write the raw values too, e.g. `on (EnterPlayModeOptionsEnabled 1, options 0)`. |
| `{{ASMDEFS}}` | Every `*.asmdef` under `Assets/` (not `Packages/` or `Library/`): name and folder. If none, write `none (all code in Assembly-CSharp)`. |
| `{{TEST_ASMDEFS}}` | The asmdefs from the row above that reference `UnityEngine.TestRunner`, list `UNITY_INCLUDE_TESTS` in `defineConstraints`, or have `"optionalUnityReferences": ["TestAssemblies"]`. If none, write `none`. |

If a file is missing or a value can't be read, write `unknown (<reason>)`. Never guess.

## 2. Write CLAUDE.md

1. Read the template at `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md` and replace every `{{...}}` placeholder.
2. If the project has no `CLAUDE.md`, write it at the project root.
3. If `CLAUDE.md` already exists, do not overwrite it. Show the user the filled template and ask whether to append it as a section, write it to `CLAUDE.unity-kit.md` instead, or skip.

## 3. Report

Print the five facts in a short list and the path written. Then:

- If domain reload is **off** and any script under `Assets/` declares a `static` field or event, suggest running the `unity-kit:unity-reviewer` agent to check that each one is reset.
- If there are no asmdefs, mention it, but do not create any; that is the user's call.
