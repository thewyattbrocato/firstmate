#!/usr/bin/env bash
# Behavioral coverage for deterministic Second Mate child-fleet reporting.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPORTER="$ROOT/bin/fm-secondmate-fleet-report.sh"
TMP_ROOT=$(fm_test_tmproot fm-secondmate-fleet-report)
MATE="$TMP_ROOT/mate"
PARENT="$TMP_ROOT/parent"
STATUS="$PARENT/state/mate.status"

cleanup() {
  fm_test_cleanup
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

command -v jq >/dev/null 2>&1 || { printf 'skip: jq not found\n'; exit 0; }

mkdir -p "$MATE/state" "$PARENT/state"
printf 'mate\n' > "$MATE/.fm-secondmate-home"
cat > "$MATE/.fm-secondmate-parent" <<EOF
schema=fm-secondmate-parent.v1
route=local
parent_home=$PARENT
EOF

write_summary() {  # <projection>
  case "$1" in
    mixed)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"captain_decision",
  "active_children":[
    {"id":"api","name":"API rollout","doing":"running contract tests"},
    {"id":"docs","name":"Operator guide","doing":"drafting recovery steps"}
  ],
  "decisions_open":[
    {"id":"deploy","key":"credential","verb":"blocked","summary":"Production deploy","reason":"release credential unavailable"},
    {"id":"route","key":"route","verb":"needs-decision","summary":"Choose the migration route","reason":"both routes have product tradeoffs"}
  ],
  "holds":[
    {"id":"vendor","title":"Vendor verification","state":"paused","reason":"vendor approval expected Friday","source":"child-state"}
  ],
  "queued":[],"landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    healthy)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"active_child_work",
  "active_children":[
    {"id":"api","name":"API rollout","doing":"running contract tests"},
    {"id":"docs","name":"Operator guide","doing":"drafting recovery steps"}
  ],
  "decisions_open":[],"holds":[],"queued":[],"landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    idle)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"no_active_work",
  "active_children":[],"decisions_open":[],"holds":[],"queued":[],"landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
  esac
}

run_reporter() {
  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$MATE" "$REPORTER"
}

write_summary mixed
run_reporter || fail "mixed child fleet did not publish"
[ "$(wc -l < "$STATUS" | tr -d '[:space:]')" -eq 1 ] \
  || fail "the first mixed fleet report was not one line"
grep -F 'needs-decision [key=secondmate-fleet]:' "$STATUS" >/dev/null \
  || fail "the mixed fleet did not request the ambiguous captain feedback"
grep -F 'Healthy progress: API rollout - running contract tests; Operator guide - drafting recovery steps' "$STATUS" >/dev/null \
  || fail "the report omitted healthy multi-child progress"
grep -F 'Stalled: Production deploy - release credential unavailable. Firstmate help: inspect and unblock Production deploy' "$STATUS" >/dev/null \
  || fail "the report omitted the stall or concrete Firstmate help"
grep -F 'Known external wait: Vendor verification - vendor approval expected Friday' "$STATUS" >/dev/null \
  || fail "the report did not distinguish the known external wait"
grep -F 'Captain feedback needed: Choose the migration route - both routes have product tradeoffs' "$STATUS" >/dev/null \
  || fail "the report omitted the genuine captain decision"
pass "one report distinguishes healthy work, a stall, an external wait, and captain feedback"

run_reporter || fail "unchanged report retry failed"
[ "$(wc -l < "$STATUS" | tr -d '[:space:]')" -eq 1 ] \
  || fail "unchanged child state emitted another report"
pass "unchanged child progress stays silent"

write_summary healthy
run_reporter || fail "resolved fleet did not publish"
[ "$(grep -c '^resolved \[key=secondmate-fleet\]:' "$STATUS")" -eq 1 ] \
  || fail "the prior aggregate blocker and decision were not explicitly resolved"
[ "$(grep -c '^working \[key=secondmate-fleet\]:' "$STATUS")" -eq 1 ] \
  || fail "the healthy replacement report was not published"
open=$(bash -c '. "$1"; status_open_decisions "$2"' _ \
  "$ROOT/bin/fm-classify-lib.sh" "$STATUS")
[ -z "$open" ] || fail "resolved aggregate decisions still look open: $open"
pass "resolution converges to healthy work without stale blockers or decisions"

write_summary mixed
run_reporter || fail "recurring semantic fleet state did not publish"
[ "$(grep -c '^needs-decision \[key=secondmate-fleet\]:' "$STATUS")" -eq 2 ] \
  || fail "a recurring fleet state was mistaken for an old retry"
pass "a recurring semantic state publishes as a new transition"

write_summary healthy
run_reporter || fail "second healthy transition did not publish"

write_summary idle
run_reporter || fail "idle resolution did not publish"
grep -F 'resolved [key=secondmate-fleet]: No active child work' "$STATUS" >/dev/null \
  || fail "active work did not resolve back to an explicit idle report"
open=$(bash -c '. "$1"; status_open_decisions "$2"' _ \
  "$ROOT/bin/fm-classify-lib.sh" "$STATUS")
[ -z "$open" ] || fail "idle fleet retained an open aggregate decision: $open"
run_reporter || fail "idle retry failed"
[ "$(grep -c 'No active child work' "$STATUS")" -eq 1 ] \
  || fail "unchanged idle state emitted another report"
pass "active work resolves idempotently back to idle"
