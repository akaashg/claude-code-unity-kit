---
name: test-fix
description: Run a Unity project's EditMode and PlayMode tests and fix the failing code in a loop until they pass. Fixes the code under test, not the test, unless the test itself is clearly wrong. Run by the user only, because a test run launches Unity and can take minutes.
argument-hint: "[editmode | playmode] [test filter]"
disable-model-invocation: true
---

# Test and fix (Unity)

Arguments: `$ARGUMENTS`. `editmode` or `playmode` goes to `--platform`; anything else is a test filter (a full test name, names separated by `;`, or a regular expression) and goes to `--filter`. With neither, the script picks the platforms from the project's test assemblies.

1. Run with the Bash tool, exactly as written and on its own (no `; echo`, pipes or `&&`), in the background (`run_in_background`), because Unity can take minutes to start and run the tests; wait for it to finish. Its last line states the result: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/test-check.sh"`, adding `--platform <editmode|playmode>` and `--filter "<filter>"` when given.
   - Exit 0: tests pass. Report the route and the counts it printed, then stop.
   - Exit 1 with `FAIL` lines: each is `FAIL <test full name> | <message> | <file:line>`, where the file is the first stack frame inside the project. Go to step 2.
   - Exit 1 with compile errors: tests didn't run. Fix the `error CS` lines as the `compile-fix` skill does, then re-run step 1.
   - Exit 4: no tests. Say so: there is no test assembly, or the test assemblies have no tests. Never call that a pass, and don't write tests unless the user asks.
   - Exit 3: not checked. Tell the user the reason it printed. If the Editor has the project open and no Unity-Skills server answers, ask them to close the Editor or run the tests from Window > General > Test Runner; never claim the tests pass.
2. Read `m_EditorVersion` in `ProjectSettings/ProjectVersion.txt`. Every API you use in a fix must exist in that version. Read the test, then the code it calls. The results XML (`Logs/unity-kit-tests-<platform>.xml`) has the full message and stack trace of each failure.
3. Decide what is wrong, per failure:
   - **The code under test** (the usual case): fix it in the project's existing style, so the test passes for the reason it was written. Never weaken a test to make it pass: don't change expected values, loosen tolerances, add `[Ignore]`, delete asserts or catch the exception the test reports.
   - **The test itself is clearly wrong**: for example it expects a value that contradicts the code's documented behaviour or a requirement the user stated, or it depends on test order or on state another test leaves behind. Don't change it on your own. Explain what is wrong with it and ask the user before editing the test.
   - **Not code**: a PlayMode test that needs a scene not in the build list, a missing package, a timeout from a slow machine. Tell the user and stop the loop for that test.
4. Re-run step 1, with `--filter` set to the tests that failed while you fix, then once without it to check nothing else broke. Stop after 5 rounds with failures remaining and summarize what is left: each test, what you changed and why it still fails.

When the Unity-Skills server runs in the Editor, the script uses it, so the Editor can stay open. It compiles first and reports **STALE** if the Editor hasn't recompiled since the last edit; ask the user to focus the Unity Editor, then re-run. If Unity-Skills refuses `test_run` (Approval mode), tell the user it needs Bypass mode or an Allowlist entry in the UnitySkills panel; don't try to get around it.
