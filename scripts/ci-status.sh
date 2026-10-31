#!/usr/bin/env bash
# Show the latest GitHub Actions run for a branch: run status, jobs, failed steps and all
# check-run annotations (path:line message). Uses only unauthenticated `curl` against the public
# GitHub REST API (works without `gh` login) and Python for JSON parsing (no jq needed).
#
# Usage:
#   scripts/ci-status.sh [options] [branch]
#
# Options:
#   -b BRANCH    Branch to inspect (default: main; a positional argument also works)
#   -r RUN_ID    Inspect this run id instead of the latest run on the branch
#   -w WORKFLOW  Workflow file name, or "all" for any workflow (default: ci.yml)
#   -R REPO      owner/repo (default: bachnguyennn/FixMySpine)
#   -A           Fetch annotations for every job, even in runs with more than 10 jobs
#   -N           Do not fetch annotations (saves API requests)
#   -h           Help
#
# Exit codes: 0 run succeeded, 1 run failed/cancelled/timed out, 3 run queued or in progress,
#             4 no runs found, 2 usage or API error (including an exhausted rate limit).
#
# Unauthenticated API limit: 60 requests/hour per IP, shared by everything on this machine.
# One invocation costs 2-3 requests + 1 per job whose annotations are fetched (5-6 jobs in this
# repo's CI, so about 8 requests). Raw logs are NOT available without authentication; that is
# why CI reports every failure as an annotation (see .github/workflows/ci.yml).
set -euo pipefail

REPO="bachnguyennn/FixMySpine"
BRANCH="main"
RUN_ID=""
WORKFLOW="ci.yml"
ANNOTATIONS="auto"
API="https://api.github.com"

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":b:r:w:R:ANh" opt; do
  case "$opt" in
    b) BRANCH="$OPTARG" ;;
    r) RUN_ID="$OPTARG" ;;
    w) WORKFLOW="$OPTARG" ;;
    R) REPO="$OPTARG" ;;
    A) ANNOTATIONS="all" ;;
    N) ANNOTATIONS="none" ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -gt 0 ]]; then BRANCH="$1"; fi

# --- Python interpreter (python3 may be the Windows Store stub, so actually run it) ---------
PY=()
for candidate in "python3" "py -3" "python"; do
  read -r -a cmd <<< "$candidate"
  if command -v "${cmd[0]}" >/dev/null 2>&1 && "${cmd[@]}" -c "import json, sys" >/dev/null 2>&1; then
    PY=("${cmd[@]}")
    break
  fi
done
if [[ ${#PY[@]} -eq 0 ]]; then
  echo "error: no working Python found (tried python3, py -3, python)" >&2
  exit 2
fi
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- JSON helper program (reads JSON on stdin) ---------------------------------------------
cat > "$TMP/parse.py" <<'PYEOF'
import json
import sys


def load():
    raw = sys.stdin.buffer.read().decode("utf-8", "replace")
    return json.loads(raw) if raw.strip() else {}


def pick_run(d):
    if "workflow_runs" in d:
        runs = d["workflow_runs"]
        return runs[0] if runs else None
    return d if "id" in d else None


def dur(start, end):
    from datetime import datetime
    try:
        f = "%Y-%m-%dT%H:%M:%SZ"
        s = (datetime.strptime(end, f) - datetime.strptime(start, f)).total_seconds()
        return f"{int(s // 60)}m{int(s % 60):02d}s"
    except Exception:
        return "-"


def outcome(item):
    return item.get("conclusion") or item.get("status") or "?"


cmd = sys.argv[1]
d = load()

if cmd == "error":
    print(d.get("message", "(no message)") if isinstance(d, dict) else d)

elif cmd == "run-field":
    run = pick_run(d)
    if run:
        value = run.get(sys.argv[2], "")
        print("" if value is None else value)

elif cmd == "run":
    run = pick_run(d)
    commit = (run.get("head_commit") or {})
    msg = (commit.get("message") or "").splitlines()[0:1]
    print(f"Run       #{run.get('run_number')}  id={run['id']}  workflow={run.get('name')}")
    print(f"Branch    {run.get('head_branch')}  sha={(run.get('head_sha') or '')[:10]}  event={run.get('event')}")
    if msg:
        print(f"Commit    {msg[0][:100]}")
    print(f"Status    {run.get('status')}  conclusion={run.get('conclusion')}  attempt={run.get('run_attempt')}")
    print(f"Created   {run.get('created_at')}  updated={run.get('updated_at')}")
    print(f"URL       {run.get('html_url')}")

elif cmd == "jobs":
    jobs = d.get("jobs", [])
    if not jobs:
        print("  (no jobs: the workflow may have failed to start, e.g. invalid YAML; open the run URL)")
    for job in jobs:
        print(f"  [{outcome(job):>9}] {job['name']}  ({dur(job.get('started_at'), job.get('completed_at'))})  job_id={job['id']}")
        for step in job.get("steps", []):
            c = step.get("conclusion")
            if c in ("failure", "cancelled", "timed_out") or (step.get("status") == "in_progress"):
                print(f"      step {step.get('number')}: {step.get('name')} -> {outcome(step)}")

elif cmd == "job-ids":
    # argv[2]: "all" = every non-skipped job; "auto" = all if <= 10 such jobs, else only
    # jobs that did not succeed (keeps big matrix runs within the 60 requests/hour limit).
    mode = sys.argv[2]
    jobs = [j for j in d.get("jobs", []) if j.get("conclusion") != "skipped"]
    if mode != "all" and len(jobs) > 10:
        jobs = [j for j in jobs if j.get("conclusion") != "success"]
        print(f"note: {len(d.get('jobs', []))} jobs; fetching annotations only for the {len(jobs)} unsuccessful ones (use -A for all).", file=sys.stderr)
    for job in jobs:
        name = job["name"].replace("\t", " ")
        print(f"{job['id']}\t{name}")

elif cmd == "rate":
    core = d.get("resources", {}).get("core", {})
    from datetime import datetime
    reset = core.get("reset")
    when = datetime.fromtimestamp(reset).strftime("%H:%M:%S") if reset else "?"
    print(f"{core.get('remaining', '?')}\t{core.get('limit', '?')}\t{when}")

elif cmd == "annotations":
    job_name = sys.argv[2]
    anns = d if isinstance(d, list) else []
    if not anns:
        sys.exit(0)
    print(f"  {job_name}: {len(anns)} annotation(s)")
    for a in anns:
        loc = a.get("path") or "?"
        if a.get("start_line"):
            loc += f":{a['start_line']}"
        level = a.get("annotation_level", "?")
        title = a.get("title") or ""
        message = (a.get("message") or "").rstrip()
        lines = message.splitlines() or [""]
        head = f"{title}: {lines[0]}" if title and title not in (lines[0], "") else lines[0]
        print(f"    {level:<8} {loc}  {head}")
        for extra in lines[1:]:
            print(f"             | {extra}")
PYEOF

PARSE="$TMP/parse.py"
if command -v cygpath >/dev/null 2>&1; then PARSE="$(cygpath -w "$PARSE")"; fi
parse() { "${PY[@]}" "$PARSE" "$@"; }

# --- HTTP helper: api <path> <outfile>; prints the HTTP status code ---------------------------
api() {
  curl -sS -L \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "User-Agent: align-ci-status" \
    -D "$TMP/headers" \
    -o "$2" \
    -w '%{http_code}' \
    "$API$1"
}

api_ok() {
  # api_ok <path> <outfile>: fetch, and exit with a readable message on HTTP errors.
  local code
  code="$(api "$1" "$2")" || { echo "error: request failed: $API$1" >&2; exit 2; }
  if [[ "$code" != "200" ]]; then
    echo "error: HTTP $code for $API$1: $(parse error < "$2")" >&2
    if [[ "$code" == "403" || "$code" == "429" ]]; then
      echo "hint: unauthenticated rate limit (60/hour) may be exhausted; see X-RateLimit-Reset." >&2
    fi
    exit 2
  fi
}

urlencode() { "${PY[@]}" -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# --- Rate limit pre-check (GET /rate_limit does not count against the quota) ----------------
if [[ "$(api "/rate_limit" "$TMP/rate.json" || true)" == "200" ]]; then
  IFS=$'\t' read -r rl_remaining rl_limit rl_reset < <(parse rate < "$TMP/rate.json")
  if [[ "$rl_remaining" =~ ^[0-9]+$ && "$rl_remaining" -lt 3 ]]; then
    echo "error: GitHub API rate limit nearly exhausted ($rl_remaining/$rl_limit left); resets at $rl_reset local time." >&2
    exit 2
  fi
fi

# --- Find the run -----------------------------------------------------------------------------
echo "Repository $REPO"
if [[ -n "$RUN_ID" ]]; then
  api_ok "/repos/$REPO/actions/runs/$RUN_ID" "$TMP/run.json"
else
  branch_q="$(urlencode "$BRANCH")"
  if [[ "$WORKFLOW" != "all" ]]; then
    code="$(api "/repos/$REPO/actions/workflows/$WORKFLOW/runs?branch=$branch_q&per_page=1" "$TMP/run.json")" || code="000"
    if [[ "$code" == "404" ]]; then
      echo "note: workflow '$WORKFLOW' not found on GitHub (not pushed yet?); showing runs of any workflow."
      WORKFLOW="all"
    elif [[ "$code" != "200" ]]; then
      echo "error: HTTP $code listing runs: $(parse error < "$TMP/run.json")" >&2
      exit 2
    fi
  fi
  if [[ "$WORKFLOW" == "all" ]]; then
    api_ok "/repos/$REPO/actions/runs?branch=$branch_q&per_page=1" "$TMP/run.json"
  fi
fi

run_id="$(parse run-field id < "$TMP/run.json")"
if [[ -z "$run_id" ]]; then
  echo "No workflow runs found for branch '$BRANCH' (workflow: $WORKFLOW)."
  exit 4
fi
parse run < "$TMP/run.json"
status="$(parse run-field status < "$TMP/run.json")"
conclusion="$(parse run-field conclusion < "$TMP/run.json")"

# --- Jobs and failed steps --------------------------------------------------------------------
echo
echo "Jobs (failed/in-progress steps listed under each job):"
api_ok "/repos/$REPO/actions/runs/$run_id/jobs?per_page=100&filter=latest" "$TMP/jobs.json"
parse jobs < "$TMP/jobs.json"

# --- Annotations (a job id is also its check-run id) -------------------------------------------
echo
if [[ "$ANNOTATIONS" == "none" ]]; then
  echo "Annotations: skipped (-N)"
else
  echo "Annotations:"
  found=0
  while IFS=$'\t' read -r job_id job_name; do
    [[ -z "$job_id" ]] && continue
    code="$(api "/repos/$REPO/check-runs/$job_id/annotations?per_page=100" "$TMP/ann.json")" || code="000"
    if [[ "$code" == "403" || "$code" == "429" ]]; then
      echo "  stopped: HTTP $code ($(parse error < "$TMP/ann.json")); remaining jobs not queried."
      break
    elif [[ "$code" != "200" ]]; then
      echo "  $job_name: could not fetch annotations (HTTP $code: $(parse error < "$TMP/ann.json"))"
      continue
    fi
    out="$(parse annotations "$job_name" < "$TMP/ann.json")"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      found=1
    fi
  done < <(parse job-ids "$ANNOTATIONS" < "$TMP/jobs.json")
  if [[ $found -eq 0 ]]; then echo "  (none)"; fi
fi

remaining="$(tr -d '\r' < "$TMP/headers" | awk -F': ' 'tolower($1) == "x-ratelimit-remaining" { v = $2 } END { print v }')"
echo
echo "API requests remaining this hour (unauthenticated): ${remaining:-unknown}"

case "$status/$conclusion" in
  completed/success) exit 0 ;;
  completed/*) exit 1 ;;
  *) exit 3 ;;
esac
