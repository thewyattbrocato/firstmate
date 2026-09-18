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
    decision-keys)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"captain_decision",
  "active_children":[],
  "decisions_open":[
    {"id":"phase8","key":"api","verb":"needs-decision","summary":"API path"},
    {"id":"phase8","key":"db","verb":"needs-decision","summary":"Database path"}
  ],
  "holds":[],"queued":[],"landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    long-decision-keys)
      local key_prefix
      key_prefix=$(printf '%100s' '' | tr ' ' k)
      jq -n --arg api_key "${key_prefix}a" --arg db_key "${key_prefix}b" '{
        schema:"fm-secondmate-home-summary.v1",
        valid:true,
        reason:null,
        invalidity:{kind:null,ids:[]},
        state:"captain_decision",
        active_children:[],
        decisions_open:[
          {id:"phase8",key:$api_key,verb:"needs-decision",summary:"Long API path"},
          {id:"phase8",key:$db_key,verb:"needs-decision",summary:"Long Database path"}
        ],
        holds:[],queued:[],landed:[],endpoints:[],counts:{},omitted:[]
      }' > "$MATE/state/home-summary.json"
      ;;
    blocked-keys)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"blocked",
  "active_children":[],
  "decisions_open":[
    {"id":"phase8","key":"api","verb":"blocked","summary":"API dependency"},
    {"id":"phase8","key":"db","verb":"blocked","summary":"Database dependency"}
  ],
  "holds":[],"queued":[],"landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    captain-deferral)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"queued",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[
    {"id":"captain-plan","title":"Choose launch window","hold_reason":"until 2026-10-01","hold_kind":"captain","hold_bucket":"dated"},
    {"id":"vendor-plan","title":"Vendor readiness","hold_reason":"vendor date pending","hold_kind":"external","hold_bucket":"dated"}
  ],
  "landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    backlog-external-hold)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"externally_held",
  "active_children":[],
  "decisions_open":[],
  "holds":[
    {"id":"vendor-contract","title":"Vendor contract","reason":"waiting on vendor signature","source":"backlog"}
  ],
  "queued":[
    {"id":"vendor-contract","title":"Vendor contract","hold_reason":"waiting on vendor signature","hold_kind":"external","hold_bucket":null}
  ],
  "landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    omitted-decisions-one)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"captain_decision",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[
    {"surface":"decisions_open","count":1}
  ]
}
EOF
      ;;
    omitted-decisions-two)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"captain_decision",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[
    {"surface":"decisions_open","count":2}
  ]
}
EOF
      ;;
    omitted-child-surfaces)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":true,
  "reason":null,
  "invalidity":{"kind":null,"ids":[]},
  "state":"active_child_work",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[
    {"surface":"active_children","count":3},
    {"surface":"holds","count":2},
    {"surface":"queued","count":1},
    {"surface":"endpoints","count":4}
  ]
}
EOF
      ;;
    invalid-orphan)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":false,
  "reason":"in-flight backlog item has no child metadata",
  "invalidity":{"kind":"orphan_in_flight","ids":["phase8"]},
  "state":"unknown",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    invalid-unowned)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":false,
  "reason":"live child state has no in-flight backlog item: provisional=working",
  "invalidity":{"kind":"unowned_current","ids":["provisional"]},
  "state":"no_active_work",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[]
}
EOF
      ;;
    invalid-unowned-provisional)
      cat > "$MATE/state/home-summary.json" <<EOF
{
  "schema":"fm-secondmate-home-summary.v1",
  "valid":false,
  "reason":"live child state has no in-flight backlog item: provisional=working",
  "invalidity":{"kind":"unowned_current","ids":["provisional"],"provisional_ids":["provisional"]},
  "state":"no_active_work",
  "active_children":[],
  "decisions_open":[],
  "holds":[],
  "queued":[],
  "landed":[],"endpoints":[],"counts":{},"omitted":[]
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

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary decision-keys
run_reporter || fail "keyed captain decisions did not publish"
grep -F 'Captain feedback needed: API path - decision required; Database path - decision required' "$STATUS" >/dev/null \
  || fail "distinct keyed decisions from one child were collapsed: $(cat "$STATUS")"
pass "distinct keyed captain decisions from one child are all reported"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary long-decision-keys
run_reporter || fail "long keyed captain decisions did not publish"
grep -F 'Captain feedback needed: Long API path - decision required; Long Database path - decision required' "$STATUS" >/dev/null \
  || fail "distinct long-prefix decisions from one child were collapsed: $(cat "$STATUS")"
pass "untruncated decision keys preserve semantic identity"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary blocked-keys
run_reporter || fail "keyed blockers did not publish"
grep -F 'Stalled: API dependency - blocked; Database dependency - blocked. Firstmate help: inspect and unblock API dependency, Database dependency' "$STATUS" >/dev/null \
  || fail "distinct keyed blockers from one child were collapsed: $(cat "$STATUS")"
pass "distinct keyed blockers from one child are all reported"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary captain-deferral
run_reporter || fail "captain deferral did not publish"
grep -F 'Known external wait: Vendor readiness - vendor date pending' "$STATUS" >/dev/null \
  || fail "non-captain dated hold was not reported as external wait: $(cat "$STATUS")"
grep -F 'Known captain deferral: Choose launch window - until 2026-10-01' "$STATUS" >/dev/null \
  || fail "dated captain hold was not reported as a captain deferral: $(cat "$STATUS")"
if grep -F 'Captain feedback needed:' "$STATUS" >/dev/null; then
  fail "deferred captain hold was reported as immediate captain feedback: $(cat "$STATUS")"
fi
pass "deferred captain holds are distinct from external waits and feedback"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary backlog-external-hold
run_reporter || fail "backlog external hold did not publish"
grep -F 'paused [key=secondmate-fleet]: Known external wait: Vendor contract - waiting on vendor signature' "$STATUS" >/dev/null \
  || fail "backlog-declared external hold was not reported as external wait: $(cat "$STATUS")"
pass "backlog-declared external holds are reported as external waits"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary omitted-decisions-one
run_reporter || fail "omitted captain decisions did not publish"
grep -F 'needs-decision [key=secondmate-fleet]: Summary incomplete: 1 additional Captain feedback item(s)' "$STATUS" >/dev/null \
  || fail "omitted captain decision count was not surfaced: $(cat "$STATUS")"
write_summary omitted-decisions-two
run_reporter || fail "changed omitted captain decision count did not publish"
[ "$(grep -c '^needs-decision \[key=secondmate-fleet\]:' "$STATUS")" -eq 2 ] \
  || fail "changed omitted decision count did not trigger a new report: $(cat "$STATUS")"
grep -F 'Summary incomplete: 2 additional Captain feedback item(s)' "$STATUS" >/dev/null \
  || fail "updated omitted captain decision count was not surfaced: $(cat "$STATUS")"
pass "omitted captain feedback counts are semantic report changes"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary omitted-child-surfaces
run_reporter || fail "omitted child surfaces did not publish"
grep -F 'paused [key=secondmate-fleet]: Summary incomplete: 3 additional healthy progress item(s); 4 additional child endpoint(s); 2 additional hold item(s); 1 additional queued item(s)' "$STATUS" >/dev/null \
  || fail "omitted child-surface counts were not surfaced as incomplete: $(cat "$STATUS")"
if grep -F 'No active child work' "$STATUS" >/dev/null; then
  fail "omitted child surfaces were reported as idle: $(cat "$STATUS")"
fi
pass "omitted child surfaces keep fleet reports visibly incomplete"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary invalid-orphan
run_reporter || fail "invalid orphan summary did not publish"
grep -F 'blocked [key=secondmate-fleet]: Stalled: orphan_in_flight - in-flight backlog item has no child metadata' "$STATUS" >/dev/null \
  || fail "invalid summary was not surfaced as a stalled fleet report: $(cat "$STATUS" 2>/dev/null || true)"
pass "invalid authoritative home summaries surface as stalled reports"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary invalid-unowned
run_reporter || fail "durable unowned-current summary did not publish"
grep -F 'blocked [key=secondmate-fleet]: Stalled: unowned_current - live child state has no in-flight backlog item: provisional=working' "$STATUS" >/dev/null \
  || fail "durable unowned-current summary was not surfaced as a stalled fleet report: $(cat "$STATUS" 2>/dev/null || true)"
pass "durable unowned-current summaries surface as stalled reports"

rm -f "$STATUS" "$MATE/state/.secondmate-fleet-report.json"
write_summary invalid-unowned-provisional
run_reporter || fail "provisional unowned-current summary should defer without failing"
assert_absent "$STATUS" "provisional unowned-current summary published a parent-facing blocker"
assert_absent "$MATE/state/.secondmate-fleet-report.json" \
  "provisional unowned-current summary recorded a delivered report receipt"
pass "provisional unowned-current summaries defer during spawn races"
