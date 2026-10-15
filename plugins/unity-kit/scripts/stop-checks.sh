#!/bin/sh
# unity-kit Stop hook: .meta pairing and the compile gate.
# Blocks stopping (exit 2, reason on stderr) when an asset lost its .meta or the project has compile errors.
# Anything that could not be checked is shown to the user as a systemMessage and does not block.

input=$(cat)
here=$(dirname "$0")

# One retry only: if Claude is already continuing because of a stop hook, let it stop.
printf '%s' "$input" | tr -d '\n' | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

PROJECT=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's#\\#/#g; s#/$##')
[ -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ] || exit 0

# Remember when we last checked, per project, so the compile gate runs only after script changes.
key=$(printf '%s' "$PROJECT" | tr -c 'A-Za-z0-9_-' '-')
state=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/unity-kit}
mkdir -p "$state" 2>/dev/null
stamp="$state/$key.last-compile-check"

block=""
info=""

meta=$(sh "$here/meta-check.sh" "$PROJECT")
case $? in
  1) block="$meta" ;;
  2) info="$meta" ;;
esac

changed=1
if [ -f "$stamp" ]; then
  changed=$(find "$PROJECT/Assets" "$PROJECT/Packages" \( -name '*.cs' -o -name '*.asmdef' -o -name '*.asmref' \) \
    -newer "$stamp" 2>/dev/null | head -n 1 | grep -c .)
fi

if [ "$changed" -gt 0 ]; then
  batch=""
  [ "$CLAUDE_PLUGIN_OPTION_BATCH_COMPILE" = "true" ] && batch="--batch"
  compile=$(sh "$here/compile-check.sh" $batch "$PROJECT")
  case $? in
    0) touch "$stamp" ;;
    1) touch "$stamp"; block="${block:+$block
}$compile" ;;
    *) info="${info:+$info
}$compile" ;;
  esac
fi

if [ -n "$block" ]; then
  printf '%s\n' "$block" "Fix these before finishing (run /unity-kit:compile-fix for compile errors)." >&2
  exit 2
fi

if [ -n "$info" ]; then
  msg=$(printf '%s' "$info" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')
  printf '{"systemMessage":"%s"}\n' "$msg"
fi
exit 0
