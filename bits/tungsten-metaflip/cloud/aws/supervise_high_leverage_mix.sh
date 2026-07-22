#!/usr/bin/env bash
# Fail-closed six-NUMA preset for the high-leverage rectangular campaign plus
# one independent 7x7 shard.  The child supervisors retain ownership of their
# own exact checkpoints; this wrapper owns cross-supervisor failure handling
# and the single terminal host-shutdown request.

set -Eeuo pipefail
set -f
export LC_ALL=C

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROGRAM=${0##*/}
RECT_SUPERVISOR=${METAFLIP_RECT_SUPERVISOR:-"$SCRIPT_DIR/supervise_rect_leaves.sh"}
SQUARE_SUPERVISOR=${METAFLIP_SQUARE_SUPERVISOR:-"$SCRIPT_DIR/supervise_7x7.sh"}

BINARY=${METAFLIP_BINARY:-}
RUNTIME_INPUT=${METAFLIP_RUNTIME_ROOT:-"$PACKAGE_ROOT/lib/metaflip"}
STATE_ROOT=${METAFLIP_STATE_ROOT:-"${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/metaflip/high-leverage-mix"}
LOG_ROOT=${METAFLIP_LOG_ROOT:-}
LOG_ROOT_EXPLICIT=0

DURATION=14400
WALKERS=64
STEPS=500000
LEASE_ROUNDS=256
POLL_SECONDS=2
DRAIN_SECONDS=120
STATUS_TIMEOUT=900
CAMPAIGN_TAG=""
SHUTDOWN_ON_EXIT=1
SHUTDOWN_COMMAND=${METAFLIP_SHUTDOWN_COMMAND:-}
DRY_RUN=0

RECT_SHAPES="4x4x5,4x5x7,4x6x7,3x4x6,2x5x6"
RECT_NODES="0,1,2,3,4"
SQUARE_NODE="5"

usage() {
  cat <<'EOF'
Usage: supervise_high_leverage_mix.sh --binary PATH [OPTIONS]

Run the measured six-NUMA world-record preset:

  node 0  4x4x5  rank 60 -> 59
  node 1  4x5x7  rank 104 -> 103
  node 2  4x6x7  rank 123 -> 122
  node 3  3x4x6  rank 54 -> 53
  node 4  2x5x6  rank 47 -> 46
  node 5  7x7    rank 247 -> 246

Required:
  --binary PATH              Native Metaflip coordinator executable

Campaign paths and lifetime:
  --runtime-root PATH        Package, lib, or lib/metaflip root
  --state-root PATH          Parent for rect/, 7x7/, and supervisor/
  --log-root PATH            Parent for rect/ and 7x7/ logs
  --seconds N                Shared wall deadline (default: 14400)
  --campaign-tag TAG         Durable tag (default includes UTC time + PID)

Work and health:
  -J, --walkers N            Walkers per NUMA shard (default: 64)
  --steps N                  Moves per worker epoch (default: 500000)
  --lease-rounds N           Rectangular private-child rounds (default: 256)
  --poll-seconds N           Cross-supervisor poll interval (default: 2)
  --drain-seconds N          TERM grace before KILL (default: 120)
  --status-timeout N         Passed to both child supervisors (default: 900)

Host policy:
  --shutdown                 Shut the host down after either supervisor ends
                             and both have drained (default)
  --no-shutdown              Leave the host running after drain
  --shutdown-command PATH    Invoke PATH instead of `sudo shutdown -h now`

Other:
  --dry-run                  Validate and print both child campaigns only
  -h, --help                 Show this help

The rectangular child supervisor is always launched with --no-shutdown.  This
wrapper sends TERM to the sibling when either supervisor ends, waits for both
exact checkpoint drains, then performs at most one shutdown request.
EOF
}

die() {
  printf '%s: %s\n' "$PROGRAM" "$*" >&2
  exit 2
}

require_uint() {
  local name=$1 value=$2
  case "$value" in
    ''|*[!0-9]*) die "$name requires a non-negative integer (got '$value')" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --binary)
      [ "$#" -ge 2 ] || die "--binary requires PATH"
      BINARY=$2
      shift 2
      ;;
    --runtime-root)
      [ "$#" -ge 2 ] || die "--runtime-root requires PATH"
      RUNTIME_INPUT=$2
      shift 2
      ;;
    --state-root)
      [ "$#" -ge 2 ] || die "--state-root requires PATH"
      STATE_ROOT=$2
      shift 2
      ;;
    --log-root)
      [ "$#" -ge 2 ] || die "--log-root requires PATH"
      LOG_ROOT=$2
      LOG_ROOT_EXPLICIT=1
      shift 2
      ;;
    --seconds)
      [ "$#" -ge 2 ] || die "--seconds requires N"
      DURATION=$2
      shift 2
      ;;
    -J|--walkers)
      [ "$#" -ge 2 ] || die "$1 requires N"
      WALKERS=$2
      shift 2
      ;;
    --steps)
      [ "$#" -ge 2 ] || die "--steps requires N"
      STEPS=$2
      shift 2
      ;;
    --lease-rounds)
      [ "$#" -ge 2 ] || die "--lease-rounds requires N"
      LEASE_ROUNDS=$2
      shift 2
      ;;
    --poll-seconds)
      [ "$#" -ge 2 ] || die "--poll-seconds requires N"
      POLL_SECONDS=$2
      shift 2
      ;;
    --drain-seconds)
      [ "$#" -ge 2 ] || die "--drain-seconds requires N"
      DRAIN_SECONDS=$2
      shift 2
      ;;
    --status-timeout)
      [ "$#" -ge 2 ] || die "--status-timeout requires N"
      STATUS_TIMEOUT=$2
      shift 2
      ;;
    --campaign-tag)
      [ "$#" -ge 2 ] || die "--campaign-tag requires TAG"
      CAMPAIGN_TAG=$2
      shift 2
      ;;
    --shutdown)
      SHUTDOWN_ON_EXIT=1
      shift
      ;;
    --no-shutdown)
      SHUTDOWN_ON_EXIT=0
      shift
      ;;
    --shutdown-command)
      [ "$#" -ge 2 ] || die "--shutdown-command requires PATH"
      SHUTDOWN_COMMAND=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      [ "$#" -eq 0 ] || die "positional arguments are not supported"
      ;;
    *)
      die "unknown option '$1'"
      ;;
  esac
done

require_uint --seconds "$DURATION"
require_uint --walkers "$WALKERS"
require_uint --steps "$STEPS"
require_uint --lease-rounds "$LEASE_ROUNDS"
require_uint --poll-seconds "$POLL_SECONDS"
require_uint --drain-seconds "$DRAIN_SECONDS"
require_uint --status-timeout "$STATUS_TIMEOUT"
[ "$WALKERS" -gt 0 ] || die "--walkers must be positive"
[ "$STEPS" -gt 0 ] || die "--steps must be positive"
[ "$LEASE_ROUNDS" -ge 1 ] && [ "$LEASE_ROUNDS" -le 256 ] || \
  die "--lease-rounds must be in 1..256"
[ "$POLL_SECONDS" -gt 0 ] || die "--poll-seconds must be positive"
[ "$DRAIN_SECONDS" -gt 0 ] || die "--drain-seconds must be positive"
[ "$STATUS_TIMEOUT" -gt 0 ] || die "--status-timeout must be positive"

[ -n "$BINARY" ] || die "--binary PATH is required"
[ -x "$BINARY" ] || die "Metaflip binary is not executable: $BINARY"
[ -x "$RECT_SUPERVISOR" ] || die "rectangular supervisor is not executable: $RECT_SUPERVISOR"
[ -x "$SQUARE_SUPERVISOR" ] || die "square supervisor is not executable: $SQUARE_SUPERVISOR"

case "$CAMPAIGN_TAG" in
  *[!A-Za-z0-9_.-]*) die "--campaign-tag may contain only letters, digits, '.', '_', and '-'" ;;
esac
if [ -z "$CAMPAIGN_TAG" ]; then
  CAMPAIGN_TAG="aws_high_leverage_$(date -u +%Y%m%dT%H%M%SZ)_$$"
fi

[ -n "$STATE_ROOT" ] || die "--state-root may not be empty"
if [ "$LOG_ROOT_EXPLICIT" -eq 0 ]; then
  LOG_ROOT="$STATE_ROOT/log"
fi
[ -n "$LOG_ROOT" ] || die "--log-root may not be empty"

RECT_COMMAND=(
  "$RECT_SUPERVISOR"
  --binary "$BINARY"
  --runtime-root "$RUNTIME_INPUT"
  --state-root "$STATE_ROOT/rect"
  --log-root "$LOG_ROOT/rect"
  --seconds "$DURATION"
  --campaign-tag "${CAMPAIGN_TAG}_rect"
  --shapes "$RECT_SHAPES"
  --nodes "$RECT_NODES"
  -J "$WALKERS"
  --steps "$STEPS"
  --lease-rounds "$LEASE_ROUNDS"
  --poll-seconds "$POLL_SECONDS"
  --drain-seconds "$DRAIN_SECONDS"
  --status-timeout "$STATUS_TIMEOUT"
  --no-shutdown
)

SQUARE_COMMAND=(
  "$SQUARE_SUPERVISOR"
  --binary "$BINARY"
  --runtime-root "$RUNTIME_INPUT"
  --tensor 7x7
  --state-root "$STATE_ROOT/7x7"
  --log-root "$LOG_ROOT/7x7"
  --seconds "$DURATION"
  --campaign-tag "${CAMPAIGN_TAG}_7x7"
  --nodes "$SQUARE_NODE"
  --shards-per-node 1
  -J "$WALKERS"
  --steps "$STEPS"
  --poll-seconds "$POLL_SECONDS"
  --drain-seconds "$DRAIN_SECONDS"
  --status-timeout "$STATUS_TIMEOUT"
)

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'PRESET campaign=%s seconds=%s J=%s steps=%s lease_rounds=%s rect_shapes=%s rect_nodes=%s square=7x7 square_node=%s shutdown=%s\n' \
    "$CAMPAIGN_TAG" "$DURATION" "$WALKERS" "$STEPS" "$LEASE_ROUNDS" \
    "$RECT_SHAPES" "$RECT_NODES" "$SQUARE_NODE" "$SHUTDOWN_ON_EXIT"
  "${RECT_COMMAND[@]}" --dry-run
  "${SQUARE_COMMAND[@]}" --dry-run
  exit 0
fi

command -v flock >/dev/null 2>&1 || die "flock is required"
if [ "$SHUTDOWN_ON_EXIT" -eq 1 ]; then
  if [ -n "$SHUTDOWN_COMMAND" ]; then
    [ -x "$SHUTDOWN_COMMAND" ] || die "shutdown command is not executable: $SHUTDOWN_COMMAND"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for host shutdown"
    command -v shutdown >/dev/null 2>&1 || die "shutdown is required for host shutdown"
  fi
fi

mkdir -p "$STATE_ROOT/supervisor" "$LOG_ROOT"
exec 9>"$STATE_ROOT/supervisor/lock"
flock -n 9 || die "another mixed supervisor holds $STATE_ROOT/supervisor/lock"

STATUS_PATH="$STATE_ROOT/supervisor/status.txt"
PIDS_PATH="$STATE_ROOT/supervisor/pids.txt"
RECT_LOG="$LOG_ROOT/rect-supervisor.log"
SQUARE_LOG="$LOG_ROOT/7x7-supervisor.log"
START_EPOCH=$(date +%s)
if [ "$DURATION" -gt 0 ]; then
  DEADLINE_EPOCH=$((START_EPOCH + DURATION))
else
  DEADLINE_EPOCH=0
fi
RECT_PID=0
SQUARE_PID=0
LAUNCHED=0
CLEAN_EXIT=0
REQUESTED_SIGNAL=""

process_alive() {
  local pid=$1 stat_line rest state=""
  [ "$pid" -gt 0 ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -r "/proc/$pid/stat" ]; then
    IFS= read -r stat_line < "/proc/$pid/stat" || return 1
    rest=${stat_line##*) }
    state=${rest%% *}
  else
    state=$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR == 1 { print substr($1, 1, 1) }')
  fi
  [ "$state" != Z ]
}

write_status() {
  local producer_state=$1 reason=$2 now elapsed rect_alive=0 square_alive=0 tmp
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  process_alive "$RECT_PID" && rect_alive=1
  process_alive "$SQUARE_PID" && square_alive=1
  tmp="$STATUS_PATH.tmp.$$.$now"
  printf '%s\n' \
    "schema=1 producer_state=$producer_state updated_epoch=$now campaign=$CAMPAIGN_TAG elapsed=$elapsed deadline_epoch=$DEADLINE_EPOCH rect_pid=$RECT_PID rect_alive=$rect_alive square_pid=$SQUARE_PID square_alive=$square_alive rect_shapes=$RECT_SHAPES square_tensor=7x7 reason=$reason" \
    > "$tmp"
  mv -f -- "$tmp" "$STATUS_PATH"
}

signal_if_alive() {
  local signal=$1 pid=$2
  if process_alive "$pid"; then
    kill -"$signal" "$pid" 2>/dev/null || true
  fi
}

emergency_cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$CLEAN_EXIT" -eq 0 ] && [ "$LAUNCHED" -gt 0 ]; then
    signal_if_alive TERM "$RECT_PID"
    signal_if_alive TERM "$SQUARE_PID"
    write_status failed "wrapper-error-$rc"
  fi
  exit "$rc"
}

trap emergency_cleanup EXIT
trap 'REQUESTED_SIGNAL=int' INT
trap 'REQUESTED_SIGNAL=term' TERM
trap 'REQUESTED_SIGNAL=hup' HUP

if [ -e "$RECT_LOG" ]; then
  mv -f -- "$RECT_LOG" "$RECT_LOG.previous.$CAMPAIGN_TAG"
fi
if [ -e "$SQUARE_LOG" ]; then
  mv -f -- "$SQUARE_LOG" "$SQUARE_LOG.previous.$CAMPAIGN_TAG"
fi
: > "$RECT_LOG"
: > "$SQUARE_LOG"
"${RECT_COMMAND[@]}" 9>&- >> "$RECT_LOG" 2>&1 &
RECT_PID=$!
LAUNCHED=1
"${SQUARE_COMMAND[@]}" 9>&- >> "$SQUARE_LOG" 2>&1 &
SQUARE_PID=$!
LAUNCHED=2

tmp="$PIDS_PATH.tmp.$$"
printf 'role=rect pid=%s log=%s state=%s\n' "$RECT_PID" "$RECT_LOG" "$STATE_ROOT/rect" > "$tmp"
printf 'role=7x7 pid=%s log=%s state=%s\n' "$SQUARE_PID" "$SQUARE_LOG" "$STATE_ROOT/7x7" >> "$tmp"
mv -f -- "$tmp" "$PIDS_PATH"

write_status running none
FINAL_REASON=""
while :; do
  if [ -n "$REQUESTED_SIGNAL" ]; then
    FINAL_REASON="signal-$REQUESTED_SIGNAL"
  elif ! process_alive "$RECT_PID"; then
    FINAL_REASON=rect-supervisor-exit
  elif ! process_alive "$SQUARE_PID"; then
    FINAL_REASON=7x7-supervisor-exit
  fi
  [ -z "$FINAL_REASON" ] || break
  write_status running none
  sleep "$POLL_SECONDS" || true
done

write_status draining "$FINAL_REASON"
signal_if_alive TERM "$RECT_PID"
signal_if_alive TERM "$SQUARE_PID"
drain_deadline=$(( $(date +%s) + DRAIN_SECONDS + 10 ))
while process_alive "$RECT_PID" || process_alive "$SQUARE_PID"; do
  now=$(date +%s)
  [ "$now" -lt "$drain_deadline" ] || break
  write_status draining "$FINAL_REASON"
  sleep "$POLL_SECONDS" || true
done
signal_if_alive KILL "$RECT_PID"
signal_if_alive KILL "$SQUARE_PID"

set +e
wait "$RECT_PID"
RECT_RC=$?
wait "$SQUARE_PID"
SQUARE_RC=$?
set -e

FINAL_STATE=stopped
EXIT_CODE=0
if [ "$RECT_RC" -ne 0 ] || [ "$SQUARE_RC" -ne 0 ]; then
  FINAL_STATE=failed
  EXIT_CODE=70
fi
case "$FINAL_REASON" in
  signal-int) EXIT_CODE=130 ;;
esac
write_status "$FINAL_STATE" "$FINAL_REASON-rect-$RECT_RC-7x7-$SQUARE_RC"

CLEAN_EXIT=1
trap - EXIT INT TERM HUP
if [ "$SHUTDOWN_ON_EXIT" -eq 1 ]; then
  set +e
  if [ -n "$SHUTDOWN_COMMAND" ]; then
    "$SHUTDOWN_COMMAND"
  else
    sudo shutdown -h now
  fi
  shutdown_rc=$?
  set -e
  if [ "$shutdown_rc" -ne 0 ]; then
    write_status failed "shutdown-command-failed-$shutdown_rc"
    exit 72
  fi
fi
exit "$EXIT_CODE"
