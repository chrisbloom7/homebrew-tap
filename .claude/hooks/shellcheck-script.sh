#!/usr/bin/env bash
# PostToolUse hook: run `shellcheck -S error` on an edited script/* file and block on error-severity findings.
# Skips quietly when jq or shellcheck is missing, so it never blocks a contributor without them.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v shellcheck >/dev/null 2>&1 || exit 0

file="$(jq -r '.tool_input.file_path // empty')"
case "${file}" in
  */script/*) ;;
  *) exit 0 ;;
esac
[ -f "${file}" ] || exit 0

if ! output="$(shellcheck -S error "${file}" 2>&1)"; then
  printf 'shellcheck errors in %s:\n%s\n' "${file}" "${output}" >&2
  exit 2
fi
exit 0
