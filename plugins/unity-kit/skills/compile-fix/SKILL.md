---
name: compile-fix
description: Compile a Unity project and fix C# compile errors in a loop until it compiles clean. Use after changing C# or asmdef files in a Unity project, when the user reports compile errors or a red Console, when the Editor is stuck in Safe Mode, or when the unity-kit Stop hook reports compile errors.
when_to_use: Triggers include "it doesn't compile", "fix the compile errors", "CS0103", "CS0246", "Safe Mode", "check it compiles".
paths: ["**/*.cs", "**/*.asmdef", "**/*.asmref"]
---

# Compile and fix (Unity)

1. Run with the Bash tool, exactly as written and on its own (no `; echo`, pipes or `&&`; its last line states the result): `sh "${CLAUDE_PLUGIN_ROOT}/scripts/compile-check.sh" --batch --state "${CLAUDE_PLUGIN_DATA}"`
   - Exit 0: compiles clean. Report the route it used and stop.
   - Exit 1: errors are listed as `File.cs(line,col): error CSxxxx: message`. Go to step 2.
   - Exit 3: not checked. Tell the user the reason it printed (stale Editor, Editor.log from another instance, no Editor found) and what to do. Do not claim it compiles.
2. Read `m_EditorVersion` in `ProjectSettings/ProjectVersion.txt`. Every API you use in a fix must exist in that version.
3. Fix the errors in the project's existing style. For CS0246/CS0234 (type or namespace not found), check the references of the asmdef that owns the file before adding `using` lines, a new asmdef or a package; ask before adding either.
4. Re-run step 1. Stop after 5 rounds with errors remaining and summarize what is left.

When the project is open in the Editor, batch mode cannot run. The script then uses Unity-Skills, the Unity CLI or Editor.log. If it reports STALE, ask the user to focus the Unity Editor so it recompiles, then re-run.
