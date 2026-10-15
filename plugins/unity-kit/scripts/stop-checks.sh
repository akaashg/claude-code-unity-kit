#!/bin/sh
# unity-kit Stop hook: .meta pairing, asset references and the compile gate.
# Blocks stopping (exit 2, reason on stderr) when an asset lost its .meta, a reference broke since the last
# commit, or the project has compile errors.
# Anything that could not be checked is shown to the user as a systemMessage and does not block.

# sed and grep return nothing on invalid UTF-8 in other locales; paths may contain any bytes.
export LC_ALL=C

input=$(cat)
here=$(dirname "$0")

# One retry only: if Claude is already continuing because of a stop hook, let it stop.
printf '%s' "$input" | tr -d '\n' | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

PROJECT=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's#\\#/#g; s#/$##')
[ -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ] || exit 0

# Clean compile results are shared with /unity-kit:compile-fix and /unity-kit:precommit through
# this folder, so a project they just compiled clean is not compiled again here.
state=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/unity-kit}

block=""
info=""

# Compile first: a batch-mode run imports new assets, so Unity has written their .meta files
# by the time the .meta check runs.
batch=""
[ "$CLAUDE_PLUGIN_OPTION_BATCH_COMPILE" = "true" ] && batch="--batch"
compile=$(sh "$here/compile-check.sh" $batch --state "$state" --if-changed "$PROJECT")
case $? in
  0) ;;
  1) block="$compile" ;;
  *) info="$compile" ;;
esac

meta=$(sh "$here/meta-check.sh" "$PROJECT")
case $? in
  1) block="${block:+$block
}$meta" ;;
  2) info="${info:+$info
}$meta" ;;
esac

refs=$(sh "$here/ref-check.sh" --state "$state" "$PROJECT")
case $? in
  1) block="${block:+$block
}$refs" ;;
  2) info="${info:+$info
}$refs" ;;
esac

if [ -n "$block" ]; then
  printf '%s\n' "$block" "Fix these before finishing (run /unity-kit:compile-fix for compile errors)." >&2
  exit 2
fi

if [ -n "$info" ]; then
  msg=$(printf '%s' "$info" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')
  printf '{"systemMessage":"%s"}\n' "$msg"
fi
exit 0
