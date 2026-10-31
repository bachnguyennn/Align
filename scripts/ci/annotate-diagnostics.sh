#!/usr/bin/env bash
# Pass-through filter that also turns compiler-style diagnostics into GitHub Actions
# annotations. Used where xcbeautify is not available (the Linux swift container, shellcheck)
# and works with bash 3.2 (macOS /bin/bash).
#
#   swift test 2>&1 | bash scripts/ci/annotate-diagnostics.sh
#   (shellcheck in gcc format) | bash scripts/ci/annotate-diagnostics.sh
#
# Recognized line shapes:
#   /abs/path/File.swift:12:5: error: message      (swiftc, clang, shellcheck -f gcc)
#   /abs/path/File.swift:12: error: Suite.test : XCTAssertEqual failed ...   (XCTest on Linux)
# Levels: error, fatal error (reported as error), warning. Notes are ignored.
# Paths under $GITHUB_WORKSPACE are made repo-relative so annotations attach to files.
# Exit status is always 0; rely on `set -o pipefail` in the caller for the real status.
set -uo pipefail

workspace="${GITHUB_WORKSPACE:-$PWD}"
workspace="${workspace%/}/"

# Workflow-command escaping (bash 3.2 compatible: no quoted replacement strings).
pct='%'
cr=$'\r'
lf=$'\n'
escape_data() {
  local s="$1"
  s="${s//"$pct"/%25}"
  s="${s//"$cr"/%0D}"
  s="${s//"$lf"/%0A}"
  printf '%s' "$s"
}

escape_prop() {
  local s
  s="$(escape_data "$1")"
  s="${s//:/%3A}"
  s="${s//,/%2C}"
  printf '%s' "$s"
}

re_col='^([^:]+\.[A-Za-z0-9]+):([0-9]+):([0-9]+): (fatal error|error|warning): (.*)$'
re_nocol='^([^:]+\.[A-Za-z0-9]+):([0-9]+): (fatal error|error|warning): (.*)$'

while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "$line"
  line="${line%"$cr"}"
  file="" lineno="" col="" level="" msg=""
  if [[ "$line" =~ $re_col ]]; then
    file="${BASH_REMATCH[1]}"; lineno="${BASH_REMATCH[2]}"; col="${BASH_REMATCH[3]}"
    level="${BASH_REMATCH[4]}"; msg="${BASH_REMATCH[5]}"
  elif [[ "$line" =~ $re_nocol ]]; then
    file="${BASH_REMATCH[1]}"; lineno="${BASH_REMATCH[2]}"
    level="${BASH_REMATCH[3]}"; msg="${BASH_REMATCH[4]}"
  else
    continue
  fi
  [[ "$level" == "fatal error" ]] && level="error"
  file="${file#"$workspace"}"
  props="file=$(escape_prop "$file"),line=$lineno"
  if [[ -n "$col" ]]; then props="$props,col=$col"; fi
  printf '::%s %s::%s\n' "$level" "$props" "$(escape_data "$msg")"
done
exit 0
