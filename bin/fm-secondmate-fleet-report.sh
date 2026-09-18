#!/usr/bin/env bash
# fm-secondmate-fleet-report.sh - report one Second Mate home's current child fleet.
#
# Usage: fm-secondmate-fleet-report.sh
#
# The command reads this home's authoritative state/home-summary.json and emits
# a concise parent-channel report only when its semantic child-fleet projection
# changes. It does not inspect worker chat, recompute current state, or maintain
# another work inventory. state/.secondmate-fleet-report.json is only a delivery
# receipt containing the last projection fingerprint, transition sequence, and
# parent-channel verb.
#
# Reports use the stable secondmate-fleet key. Before replacing an earlier
# report, the command publishes an exact-key resolved line so an old blocker,
# wait, or captain decision cannot remain open after the home summary changes.
# Repeated execution converges: parent-channel exact-line deduplication and the
# atomic receipt make an interrupted retry safe.
#
# Main homes and incomplete fixture homes without a parent binding are no-ops.
# A seeded Second Mate with a malformed summary, unsafe receipt, or unavailable
# parent channel fails so fm-home-summary-refresh.sh can surface the publication
# failure through its existing diagnostic path.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
SUMMARY="$STATE/home-summary.json"
RECEIPT="$STATE/.secondmate-fleet-report.json"

# shellcheck source=bin/fm-parent-channel-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-parent-channel-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-wake-lib.sh"

die() {
  printf 'fm-secondmate-fleet-report: %s\n' "$1" >&2
  exit 1
}

sha256_text() {  # <text>
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    return 1
  fi
}

write_receipt() {  # <fingerprint> <verb> <sequence>
  local fingerprint=$1 verb=$2 sequence=$3 tmp
  tmp=$(umask 077; mktemp "$STATE/.secondmate-fleet-report.json.XXXXXX") \
    || return 1
  if ! jq -n --arg fingerprint "$fingerprint" --arg verb "$verb" \
      --argjson sequence "$sequence" \
      '{schema:"fm-secondmate-fleet-report.v1",fingerprint:$fingerprint,verb:$verb,sequence:$sequence}' \
      > "$tmp" \
    || ! chmod 600 "$tmp" \
    || ! mv -f -- "$tmp" "$RECEIPT"; then
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi
}

summary_has_provisional_unowned_child() {
  local id lock
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    lock=$(fm_meta_lock_path "$STATE/$id.meta" 2>/dev/null) || continue
    if fm_lock_try_acquire "$lock"; then
      fm_lock_release "$lock" || true
      continue
    fi
    return 0
  done <<EOF
$(jq -r '
    select(.schema == "fm-secondmate-home-summary.v1")
    | select(.invalidity.kind == "unowned_current")
    | .invalidity.ids[]?
    | tostring
  ' "$SUMMARY")
EOF
  return 1
}

[ -e "$FM_HOME/.fm-secondmate-home" ] || exit 0
[ -e "$FM_HOME/.fm-secondmate-parent" ] || exit 0
command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "$SUMMARY" ] && [ ! -L "$SUMMARY" ] \
  || die "authoritative home summary is unavailable"

if summary_has_provisional_unowned_child; then
  exit 0
fi

projection=$(jq -cS '
  def text($n):
    tostring | gsub("[\\t\\r\\n]+"; " ") | gsub("  +"; " ")
    | if length > $n then .[:$n] else . end;
  def item($id; $key; $label; $reason):
    {id:($id | tostring),key:($key | tostring),label:($label | text(100)),reason:($reason | text(160))};
  def items_text:
    map(.label + (if .reason == "" then "" else " - " + .reason end)) | join("; ");
  def omitted_label:
    if .surface == "active_children" then "healthy progress item(s)"
    elif .surface == "decisions_open" then "Captain feedback item(s)"
    elif .surface == "holds" then "hold item(s)"
    elif .surface == "queued" then "queued item(s)"
    elif .surface == "endpoints" then "child endpoint(s)"
    else .surface end;
  def omitted_text:
    map((.count | tostring) + " additional " + omitted_label) | join("; ");
  if .schema != "fm-secondmate-home-summary.v1" then error("unsupported home-summary schema") else . end
  | ([.omitted[]?
      | select(.surface == "active_children" or .surface == "decisions_open" or .surface == "holds" or .surface == "queued" or .surface == "endpoints")
      | {surface:(.surface | tostring),count:(.count | tonumber? // 0)}
      | select(.count > 0)] | sort_by(.surface)) as $omitted
  | ([.active_children[]?
      | item(.id; .id; (.name // .id); (.doing // "in progress"))] | unique_by(.id)) as $healthy
  | ([.decisions_open[]?
      | select(.verb == "needs-decision" or .verb == "captain-hold")
      | item(.id; (.key // .summary // .id); (.summary // .id); (.reason // "decision required"))] | unique_by([.id, .key, .reason])) as $captain
  | ([.decisions_open[]?
      | select(.verb == "blocked")
      | item(.id; (.key // .summary // .id); (.summary // .id); (.reason // "blocked"))]
      + [.holds[]?
         | select(.source == "child-state" and (.state == "blocked" or .state == "parked"))
         | item(.id; .id; (.title // .id); (.reason // .state))]
      + [.queued[]?
         | select((.unresolved_blocker_ids // [] | length) > 0)
         | item(.id; .id; (.title // .id);
             (if (.blocked_reason // "") != "" then .blocked_reason
              else "waiting on " + (.unresolved_blocker_ids | join(", ")) end))]
      + [if .valid == false then
           item("home-summary"; (.invalidity.kind // "invalid"); (.invalidity.kind // "invalid home summary"); (.reason // "current progress cannot be verified"))
         else empty end]
      | unique_by([.id, .key, .reason])) as $stalled
  | ([.holds[]?
      | select(.source == "child-state" and .state == "paused")
      | item(.id; .id; (.title // .id); (.reason // "external wait"))]
      + [.queued[]?
         | select((.hold_kind // "") != "captain" and ((.hold_bucket == "dated" or .hold_bucket == "aged") or (.hold_reason // null) != null))
         | item(.id; .id; (.title // .id); (.hold_reason // "external wait"))]
      | unique_by([.id, .reason])) as $waiting
  | ([.queued[]?
      | select((.hold_kind // "") == "captain" and (.hold_bucket == "dated" or .hold_bucket == "aged"))
      | item(.id; .id; (.title // .id); (.hold_reason // .hold_bucket // "captain deferral"))]
      | unique_by([.id, .reason])) as $deferred
  | (if ($captain | length) > 0 or any($omitted[]; .surface == "decisions_open") then "needs-decision"
     elif ($stalled | length) > 0 then "blocked"
     elif ($waiting | length) > 0 then "paused"
     elif ($deferred | length) > 0 then "paused"
     elif ($omitted | length) > 0 then "paused"
     elif ($healthy | length) > 0 then "working"
     else "resolved" end) as $verb
  | ([if ($healthy | length) > 0 then "Healthy progress: " + ($healthy | items_text) else empty end,
      if ($stalled | length) > 0 then
        "Stalled: " + ($stalled | items_text) + ". Firstmate help: inspect and unblock " + ($stalled | map(.label) | join(", "))
      else empty end,
      if ($waiting | length) > 0 then "Known external wait: " + ($waiting | items_text) else empty end,
      if ($deferred | length) > 0 then "Known captain deferral: " + ($deferred | items_text) else empty end,
      if ($captain | length) > 0 then "Captain feedback needed: " + ($captain | items_text) else empty end,
      if ($omitted | length) > 0 then "Summary incomplete: " + ($omitted | omitted_text) else empty end]
     | if length == 0 then "No active child work" else join(". ") end) as $note
  | {verb:$verb,note:$note,healthy:$healthy,stalled:$stalled,waiting:$waiting,deferred:$deferred,captain:$captain,omitted:$omitted}
' "$SUMMARY") || die "could not derive a child-fleet report from the home summary"

fingerprint=$(sha256_text "$projection") || die "shasum or sha256sum is required"
verb=$(printf '%s' "$projection" | jq -r '.verb')
note=$(printf '%s' "$projection" | jq -r '.note')
note=$(fm_parent_channel_clean_note "$note")
short=${fingerprint%"${fingerprint#????????}"}
previous_fingerprint=
previous_verb=
previous_sequence=0

if [ -e "$RECEIPT" ] || [ -L "$RECEIPT" ]; then
  [ -f "$RECEIPT" ] && [ ! -L "$RECEIPT" ] \
    || die "delivery receipt is not a regular file"
  jq -e '.schema == "fm-secondmate-fleet-report.v1"
    and (.fingerprint | type) == "string"
    and (.verb | type) == "string"' "$RECEIPT" >/dev/null 2>&1 \
    || die "delivery receipt is malformed"
  previous_fingerprint=$(jq -r '.fingerprint' "$RECEIPT")
  previous_verb=$(jq -r '.verb' "$RECEIPT")
  previous_sequence=$(jq -r '.sequence // 0' "$RECEIPT")
  case "$previous_sequence" in
    ''|*[!0-9]*) die "delivery receipt has an invalid transition sequence" ;;
  esac
fi

[ "$fingerprint" != "$previous_fingerprint" ] || exit 0

# An initially idle home stays silent, but recording its baseline lets a later
# active-to-idle transition publish the required resolution.
if [ -z "$previous_fingerprint" ] && [ "$verb" = resolved ]; then
  write_receipt "$fingerprint" "$verb" 0 || die "could not record the idle baseline"
  exit 0
fi

sequence=$((previous_sequence + 1))

if [ -n "$previous_fingerprint" ] && [ "$previous_verb" != resolved ]; then
  previous_short=${previous_fingerprint%"${previous_fingerprint#????????}"}
  fm_parent_channel_report "$FM_HOME" "$STATE" \
    "resolved [key=secondmate-fleet]: Previous crew summary $previous_short/$previous_sequence is superseded" \
    || die "could not close the previous parent report"
fi

fm_parent_channel_report "$FM_HOME" "$STATE" \
  "$verb [key=secondmate-fleet]: $note [report=$short/$sequence]" \
  || die "could not publish the current child-fleet report"
write_receipt "$fingerprint" "$verb" "$sequence" || die "could not record the delivered report"
