#!/usr/bin/env bash
# Emits one GitHub Actions error annotation summarizing a failed step's raw log:
# the first lines that look like errors, then the last lines of the log.
#
#   bash scripts/ci/annotate-log-tail.sh <log-file> <title> [tail-lines]
#
# Why: CI logs are not readable without an authenticated `gh`, but check-run annotations are
# public. xcbeautify/swift-annotate.sh only annotate diagnostics they recognize; this catches
# everything else (xcodegen errors, missing schemes, linker errors, crashes, pip failures).
set -uo pipefail

log="${1:?usage: annotate-log-tail.sh <log-file> <title> [tail-lines]}"
title="${2:-Step failed}"
tail_lines="${3:-30}"

if [[ ! -s "$log" ]]; then
  echo "::error title=$title::Step failed and produced no log output ($log missing or empty)."
  exit 0
fi

pct='%'
cr=$'\r'
lf=$'\n'
esc=$'\033'

clean() {
  # Strip ANSI colour codes and truncate very long lines.
  sed -e "s/${esc}\[[0-9;]*[A-Za-z]//g" | cut -c1-240
}

errors="$(grep -E '(error|Error|ERROR|fatal|FAILED|failed|Fatal)[: ]' "$log" | clean | awk '!seen[$0]++' | head -n 25)"
tail_text="$(tail -n "$tail_lines" "$log" | clean)"

msg=""
if [[ -n "$errors" ]]; then
  msg="Error-like lines (first 25):${lf}${errors}${lf}${lf}"
fi
msg="${msg}Last ${tail_lines} log lines:${lf}${tail_text}"

msg="${msg//"$pct"/%25}"
msg="${msg//"$cr"/}"
msg="${msg//"$lf"/%0A}"
title="${title//"$pct"/%25}"
title="${title//:/%3A}"
title="${title//,/%2C}"

printf '::error title=%s::%s\n' "$title" "$msg"
