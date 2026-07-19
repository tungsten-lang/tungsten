#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUPERVISOR="$SCRIPT_DIR/supervise_rect_leaves.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-rect-supervisor.XXXXXX")
MUTATOR_PID=""
cleanup() {
  if [ -n "$MUTATOR_PID" ]; then
    kill "$MUTATOR_PID" 2>/dev/null || true
    wait "$MUTATOR_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT INT TERM HUP

RUNTIME="$TMP_ROOT/runtime"
FAKE_TOOLS="$TMP_ROOT/fake-tools"
FAKE_BINARY="$TMP_ROOT/metaflip"
FAKE_SHUTDOWN="$TMP_ROOT/fake-shutdown"
NUMA_ROOT="$TMP_ROOT/numa"
CGROUP_EVENTS="$TMP_ROOT/memory.events"
mkdir -p "$RUNTIME" "$FAKE_TOOLS" "$NUMA_ROOT/node0" "$NUMA_ROOT/node1"

cat > "$RUNTIME/fleet.w" <<'EOF'
switch_options = ["--rect-portfolio-child"]
value_options = ["--rect-restart-nonce", "--rect-door-ticket"]
EOF

cat > "$FAKE_TOOLS/setsid" <<'EOF'
#!/bin/sh
exec "$@"
EOF

cat > "$FAKE_TOOLS/numactl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cpunodebind=*|--membind=*) shift ;;
    *) break ;;
  esac
done
exec "$@"
EOF

cat > "$FAKE_TOOLS/flock" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$FAKE_BINARY" <<'EOF'
#!/usr/bin/env bash
# Native marker fixtures: --rect-portfolio-child --rect-restart-nonce
# --rect-door-ticket
set -eu
shape=""
status=""
best=""
cpu_lanes=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tensor) shape=$2; shift 2 ;;
    --status) status=$2; shift 2 ;;
    --best) best=$2; shift 2 ;;
    -J) cpu_lanes=$2; shift 2 ;;
    --runtime-root|--state-dir|--near-dir|--run-tag|--steps|--secs|--rect-restart-nonce|--rect-door-ticket)
      shift 2
      ;;
    --no-gpu|--quiet|--no-tui|--stop-on-record|--rect-portfolio-child)
      shift
      ;;
    *)
      printf 'unexpected fake Metaflip argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done
[ -n "$shape" ] && [ -n "$status" ] && [ -n "$best" ]
case "$shape" in
  2x3x5) record=25 ;;
  3x4x4) record=38 ;;
  *) record=99 ;;
esac
target=$((record - 1))
rank=$record
producer_state=running
wr_gap=0
wr_status=ties
cpu_moves=100
gpu_moves=23
if [ "${FAKE_METAFLIP_RECORD_SHAPE:-}" = "$shape" ]; then
  rank=$target
  producer_state=stopped
  wr_gap=-1
  wr_status=beats
  cpu_moves=101
  gpu_moves=24
fi
if [ "${FAKE_METAFLIP_STALE_RECORD_SHAPE:-}" = "$shape" ]; then
  rank=$target
  producer_state=stopped
  wr_gap=-1
  wr_status=beats
fi
printf '%s\n1 1 1\n' "$rank" > "$best"
tmp="$status.tmp.$$"
printf 'schema=1 mode=rect producer_state=%s sequence=1 tensor=%s record=%s record_known=1 target=%s best_rank=%s best_bits=999 wr_gap=%s wr_status=%s cpu_lanes=%s cpu_moves=%s cpu_ms=10 gpu_requested=0 gpu_supported=0 gpu_ready=0 gpu_lanes=0 gpu_moves=%s gpu_ms=0 gpu_failures=0 exact_rejects=0 elapsed=1\n' \
  "$producer_state" "$shape" "$record" "$target" "$rank" "$wr_gap" "$wr_status" "$cpu_lanes" "$cpu_moves" "$gpu_moves" > "$tmp"
mv -f "$tmp" "$status"
if [ "${FAKE_METAFLIP_STALE_RECORD_SHAPE:-}" = "$shape" ]; then
  touch -t 200001010000 "$status"
  exit 0
fi
if [ "${FAKE_METAFLIP_RECORD_SHAPE:-}" = "$shape" ]; then
  exit 0
fi
if [ "${FAKE_METAFLIP_EXIT_SHAPE:-}" = "$shape" ]; then
  exit "${FAKE_METAFLIP_EXIT_CODE:-17}"
fi
trap 'exit 0' TERM INT HUP
while :; do sleep 1; done
EOF

cat > "$FAKE_SHUTDOWN" <<'EOF'
#!/bin/sh
printf 'shutdown\n' >> "$FAKE_SHUTDOWN_LOG"
EOF

chmod +x "$FAKE_TOOLS/setsid" "$FAKE_TOOLS/numactl" "$FAKE_TOOLS/flock" "$FAKE_BINARY" "$FAKE_SHUTDOWN"
printf 'oom 0\noom_kill 0\n' > "$CGROUP_EVENTS"

failures=0
expect() {
  local label=$1
  shift
  if "$@"; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

expect_token() {
  local label=$1 path=$2 token=$3
  expect "$label" grep -Eq "(^| )${token}( |$)" "$path"
}

supervisor_env() {
  local vmstat=$1 shutdown_log=$2
  shift 2
  env \
    PATH="$FAKE_TOOLS:$PATH" \
    METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
    METAFLIP_VMSTAT_PATH="$vmstat" \
    METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
    FAKE_SHUTDOWN_LOG="$shutdown_log" \
    "$SUPERVISOR" "$@"
}

COMMON_ARGS=(
  --binary "$FAKE_BINARY"
  --runtime-root "$RUNTIME"
  --shapes 2x3x5,3x4x4
  --nodes 0,1
  -J 3
  --steps 77
  --poll-seconds 1
  --drain-seconds 1
  --status-timeout 30
  --shutdown-command "$FAKE_SHUTDOWN"
)

# Dry-run validates the complete leaf protocol without creating state or
# invoking the (fake) shutdown command.
DRY_STATE="$TMP_ROOT/dry-state"
DRY_LOG="$TMP_ROOT/dry-log"
DRY_OUTPUT="$TMP_ROOT/dry-run.txt"
DRY_SHUTDOWN_LOG="$TMP_ROOT/dry-shutdown.log"
VMSTAT_DRY="$TMP_ROOT/vmstat-dry"
printf 'oom_kill 0\n' > "$VMSTAT_DRY"
supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" \
  --state-root "$DRY_STATE" \
  --log-root "$DRY_LOG" \
  --seconds 17 \
  --campaign-tag dry-test \
  --dry-run \
  > "$DRY_OUTPUT"

leaf_count=$(grep -c '^DRY_RUN leaf=' "$DRY_OUTPUT" || true)
expect 'dry-run emits one leaf per shape/node pair' test "$leaf_count" -eq 2
expect 'node 0 is CPU- and memory-bound' grep -q -- '--cpunodebind=0 --membind=0' "$DRY_OUTPUT"
expect 'node 1 is CPU- and memory-bound' grep -q -- '--cpunodebind=1 --membind=1' "$DRY_OUTPUT"
expect 'explicit CPU walker and step budgets survive construction' grep -q -- '-J 3 --steps 77' "$DRY_OUTPUT"
expect 'children are CPU-only, headless, and record-stopping' grep -q -- '--no-gpu --quiet --no-tui --stop-on-record' "$DRY_OUTPUT"
private_count=$(grep -c -- '--rect-portfolio-child --rect-restart-nonce' "$DRY_OUTPUT" || true)
expect 'every command uses the private rectangular leaf protocol' test "$private_count" -eq 2
expect 'leaf restart nonces are distinct and positive' grep -q -- '--rect-restart-nonce 1' "$DRY_OUTPUT"
expect 'second leaf advances restart nonce and door ticket' grep -q -- '--rect-restart-nonce 2 --rect-door-ticket 1' "$DRY_OUTPUT"
expect 'supervisor, not children, owns the wall deadline' grep -q -- '--secs 0' "$DRY_OUTPUT"
expect 'dry-run writes no state root' test ! -e "$DRY_STATE"
expect 'dry-run writes no log root' test ! -e "$DRY_LOG"
expect 'dry-run never invokes shutdown' test ! -e "$DRY_SHUTDOWN_LOG"

# All topology/shape errors must fail before any state or shutdown action.
INVALID_OUTPUT="$TMP_ROOT/invalid.txt"
if supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" --shapes 3x3x3,3x4x4 --nodes 0,1 --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  invalid_square_rc=0
else
  invalid_square_rc=$?
fi
expect 'square tensors are rejected as rectangular leaves' test "$invalid_square_rc" -eq 2
expect 'square rejection explains the rectangular contract' grep -q -- 'unsupported rectangular shape' "$INVALID_OUTPUT"

if supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" --shapes 2x3x5 --nodes 0,1 --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  mismatch_rc=0
else
  mismatch_rc=$?
fi
expect 'shape/node count mismatch is rejected' test "$mismatch_rc" -eq 2

if supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" --nodes 0,0 --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  duplicate_node_rc=0
else
  duplicate_node_rc=$?
fi
expect 'duplicate NUMA assignments are rejected' test "$duplicate_node_rc" -eq 2

OLD_BINARY="$TMP_ROOT/metaflip-without-rect-leaf-options"
printf '#!/bin/sh\nexit 0\n' > "$OLD_BINARY"
chmod +x "$OLD_BINARY"
if supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" --binary "$OLD_BINARY" --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  old_binary_rc=0
else
  old_binary_rc=$?
fi
expect 'runtime/old-binary rectangular option mismatch is rejected' test "$old_binary_rc" -eq 2
expect 'binary mismatch names the absent leaf option' grep -q -- 'native binary does not advertise required rectangular option' "$INVALID_OUTPUT"
expect 'validation failures never invoke shutdown' test ! -e "$DRY_SHUTDOWN_LOG"

# A deadline drains both children, atomically publishes final status, and calls
# only the injected shutdown helper.
DEADLINE_STATE="$TMP_ROOT/deadline-state"
DEADLINE_LOG="$TMP_ROOT/deadline-log"
DEADLINE_SHUTDOWN_LOG="$TMP_ROOT/deadline-shutdown.log"
VMSTAT_DEADLINE="$TMP_ROOT/vmstat-deadline"
printf 'oom_kill 0\n' > "$VMSTAT_DEADLINE"
if supervisor_env "$VMSTAT_DEADLINE" "$DEADLINE_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" \
  --state-root "$DEADLINE_STATE" \
  --log-root "$DEADLINE_LOG" \
  --seconds 1 \
  --campaign-tag deadline-test \
  > "$TMP_ROOT/deadline.stdout" 2> "$TMP_ROOT/deadline.stderr"; then
  deadline_rc=0
else
  deadline_rc=$?
fi
DEADLINE_STATUS="$DEADLINE_STATE/supervisor/status.txt"
expect 'deadline is a clean supervisor result' test "$deadline_rc" -eq 0
expect_token 'deadline status is stopped' "$DEADLINE_STATUS" 'producer_state=stopped'
expect_token 'deadline reason is durable' "$DEADLINE_STATUS" 'reason=deadline'
expect_token 'both leaf heartbeats were aggregated' "$DEADLINE_STATUS" 'status_count=2'
expect_token 'final status has no running children' "$DEADLINE_STATUS" 'running_count=0'
expect_token 'moves are summed across leaves' "$DEADLINE_STATUS" 'total_moves=246'
expect 'per-shape objectives remain separate in aggregate status' grep -q -- 'best_by_shape=2x3x5:25:999,3x4x4:38:999' "$DEADLINE_STATUS"
shutdown_count=$(wc -l < "$DEADLINE_SHUTDOWN_LOG" | tr -d ' ')
expect 'deadline invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1
leftover_tmp=$(find "$DEADLINE_STATE/supervisor" -name '*.tmp.*' -print -quit)
expect 'atomic status/manifest replacement leaves no temp files' test -z "$leftover_tmp"

# A clean --stop-on-record child exit is the one expected early-exit case. Its
# production status must prove the objective before the sibling is drained.
RECORD_STATE="$TMP_ROOT/record-state"
RECORD_LOG="$TMP_ROOT/record-log"
RECORD_SHUTDOWN_LOG="$TMP_ROOT/record-shutdown.log"
VMSTAT_RECORD="$TMP_ROOT/vmstat-record"
printf 'oom_kill 0\n' > "$VMSTAT_RECORD"
if env FAKE_METAFLIP_RECORD_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_RECORD" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$RECORD_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --state-root "$RECORD_STATE" \
  --log-root "$RECORD_LOG" \
  --seconds 20 \
  --campaign-tag record-test \
  > "$TMP_ROOT/record.stdout" 2> "$TMP_ROOT/record.stderr"; then
  record_rc=0
else
  record_rc=$?
fi
RECORD_STATUS="$RECORD_STATE/supervisor/status.txt"
expect 'verified record child exit is successful' test "$record_rc" -eq 0
expect_token 'record terminal status is stopped' "$RECORD_STATUS" 'producer_state=stopped'
expect_token 'record reason names the winning shape' "$RECORD_STATUS" 'reason=record-2x3x5'
expect_token 'record drain leaves no sibling running' "$RECORD_STATUS" 'running_count=0'
expect 'record status retains the winning rank/density' grep -q -- 'best_by_shape=2x3x5:24:999' "$RECORD_STATUS"
record_rank=$(sed -n '1p' "$RECORD_STATE/2x3x5/best.txt")
expect 'record best artifact is durable before shutdown' test "$record_rank" -eq 24
shutdown_count=$(wc -l < "$RECORD_SHUTDOWN_LOG" | tr -d ' ')
expect 'record stop invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# A stopped record-looking status older than its child cannot authorize an
# early-success shutdown. This models a stale snapshot surviving an interrupted
# launcher or being restored from durable state before the new child exits.
STALE_STATE="$TMP_ROOT/stale-state"
STALE_LOG="$TMP_ROOT/stale-log"
STALE_SHUTDOWN_LOG="$TMP_ROOT/stale-shutdown.log"
VMSTAT_STALE="$TMP_ROOT/vmstat-stale"
printf 'oom_kill 0\n' > "$VMSTAT_STALE"
if env FAKE_METAFLIP_STALE_RECORD_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_STALE" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$STALE_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --state-root "$STALE_STATE" \
  --log-root "$STALE_LOG" \
  --seconds 20 \
  --campaign-tag stale-record-test \
  > "$TMP_ROOT/stale.stdout" 2> "$TMP_ROOT/stale.stderr"; then
  stale_record_rc=0
else
  stale_record_rc=$?
fi
STALE_STATUS="$STALE_STATE/supervisor/status.txt"
expect 'pre-launch record snapshot cannot authorize success' test "$stale_record_rc" -eq 70
expect_token 'stale-record status is failed' "$STALE_STATUS" 'producer_state=failed'
expect_token 'stale-record exit remains an ordinary child failure' "$STALE_STATUS" 'reason=child-2x3x5-exit-0'
shutdown_count=$(wc -l < "$STALE_SHUTDOWN_LOG" | tr -d ' ')
expect 'stale record still invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# An arbitrary early exit is fail-closed: the sibling drains and the host
# shutdown request still happens, but the supervisor returns failure.
EXIT_STATE="$TMP_ROOT/exit-state"
EXIT_LOG="$TMP_ROOT/exit-log"
EXIT_SHUTDOWN_LOG="$TMP_ROOT/exit-shutdown.log"
VMSTAT_EXIT="$TMP_ROOT/vmstat-exit"
printf 'oom_kill 0\n' > "$VMSTAT_EXIT"
if env FAKE_METAFLIP_EXIT_SHAPE=2x3x5 FAKE_METAFLIP_EXIT_CODE=17 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_EXIT" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$EXIT_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --state-root "$EXIT_STATE" \
  --log-root "$EXIT_LOG" \
  --seconds 20 \
  --campaign-tag child-exit-test \
  > "$TMP_ROOT/exit.stdout" 2> "$TMP_ROOT/exit.stderr"; then
  child_exit_rc=0
else
  child_exit_rc=$?
fi
EXIT_STATUS="$EXIT_STATE/supervisor/status.txt"
expect 'early child exit fails the supervisor' test "$child_exit_rc" -eq 70
expect_token 'child-exit status is failed' "$EXIT_STATUS" 'producer_state=failed'
expect_token 'child-exit reason identifies shape and code' "$EXIT_STATUS" 'reason=child-2x3x5-exit-17'
expect_token 'child-exit drain leaves no sibling running' "$EXIT_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$EXIT_SHUTDOWN_LOG" | tr -d ' ')
expect 'child exit invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# A changing kernel OOM counter is also fail-closed. The counter is a regular
# fixture file, so this test never perturbs host memory or cgroup state.
OOM_STATE="$TMP_ROOT/oom-state"
OOM_LOG="$TMP_ROOT/oom-log"
OOM_SHUTDOWN_LOG="$TMP_ROOT/oom-shutdown.log"
VMSTAT_OOM="$TMP_ROOT/vmstat-oom"
printf 'oom_kill 0\n' > "$VMSTAT_OOM"
(
  sleep 1
  printf 'oom_kill 1\n' > "$VMSTAT_OOM"
) &
MUTATOR_PID=$!
if supervisor_env "$VMSTAT_OOM" "$OOM_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" \
  --state-root "$OOM_STATE" \
  --log-root "$OOM_LOG" \
  --seconds 20 \
  --campaign-tag oom-test \
  > "$TMP_ROOT/oom.stdout" 2> "$TMP_ROOT/oom.stderr"; then
  oom_rc=0
else
  oom_rc=$?
fi
wait "$MUTATOR_PID" 2>/dev/null || true
MUTATOR_PID=""
OOM_STATUS="$OOM_STATE/supervisor/status.txt"
expect 'OOM counter increase has a distinct failure code' test "$oom_rc" -eq 71
expect_token 'OOM status is failed' "$OOM_STATUS" 'producer_state=failed'
expect_token 'OOM reason is durable' "$OOM_STATUS" 'reason=oom-counter-increased'
expect_token 'increased kernel OOM counter is published' "$OOM_STATUS" 'oom_vm=1'
expect_token 'OOM drain leaves no child running' "$OOM_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$OOM_SHUTDOWN_LOG" | tr -d ' ')
expect 'OOM invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d rectangular supervisor assertion(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: rectangular AWS/NUMA supervisor contract\n'
