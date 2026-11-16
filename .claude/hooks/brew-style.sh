#!/usr/bin/env bash
# PostToolUse hook: autocorrect an edited formula with `brew style --fix` and report what is left.
# Skips quietly when jq or brew is missing, so it never blocks a contributor without them.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v brew >/dev/null 2>&1 || exit 0

file="$(jq -r '.tool_input.file_path // empty')"
case "${file}" in
  */Formula/*.rb) ;;
  *) exit 0 ;;
esac
[ -f "${file}" ] || exit 0

if ! output="$(brew style --fix "${file}" 2>&1)"; then
  printf 'brew style offenses left in %s:\n%s\n' "${file}" "${output}" >&2
  exit 2
fi
exit 0
