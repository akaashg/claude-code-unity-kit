# Contributing

## Rules need a source

Every rule, hook and agent check must come from a real problem someone hit in a Unity project. Add the source to [docs/SOURCES.md](docs/SOURCES.md) in the same pull request: an issue, a Unity bug report or doc page, or a short description of what went wrong. Rules from general best-practice lists won't be merged.

## Core or pack?

Generic Unity 6 rules go in `plugins/unity-kit`. Anything tied to a platform, SDK or vendor package goes in a pack; see [docs/PACKS.md](docs/PACKS.md).

## Keep skills short

A skill that fires reliably beats a long one that doesn't. Put the trigger first in `description`, keep `SKILL.md` to what Claude must do, and move reference material to separate files.

## Before opening a pull request

```bash
claude plugin validate --strict plugins/unity-kit
claude plugin validate --strict .
sh tests/hooks.test.sh
```

Hook scripts are POSIX `sh`: they must run on macOS `sh` and Git Bash on Windows, without jq, Node or Python. Use `sed -E` rather than GNU-only `\|`, and don't rely on backslashes inside bracket expressions.

If you tested against a real Unity version, add it to [docs/TESTED.md](docs/TESTED.md).
