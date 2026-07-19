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
switch_options = ["--rect", "--rect-portfolio-child"]
value_options = ["--rect-shapes", "--rect-epoch-rounds", "--rect-restart-nonce", "--rect-door-ticket"]
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
[ "${FAKE_FLOCK_FAIL:-0}" -eq 0 ] || exit 1
exit 0
EOF

cat > "$FAKE_BINARY" <<'EOF'
#!/usr/bin/env bash
# Native marker fixtures: --rect --rect-shapes --rect-epoch-rounds
# --rect-portfolio-child --rect-restart-nonce --rect-door-ticket
set -eu
shape=""
status=""
state_dir=""
cpu_lanes=0
lease_rounds=0
parent=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --rect) parent=1; shift ;;
    --rect-shapes) shape=$2; shift 2 ;;
    --rect-epoch-rounds) lease_rounds=$2; shift 2 ;;
    --status) status=$2; shift 2 ;;
    --state-dir) state_dir=$2; shift 2 ;;
    -J) cpu_lanes=$2; shift 2 ;;
    --runtime-root|--run-tag|--steps|--rounds|--secs)
      shift 2
      ;;
    --no-gpu|--quiet|--no-tui|--stop-on-record)
      shift
      ;;
    *)
      printf 'unexpected fake Metaflip argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done
[ "$parent" -eq 1 ] && [ "$lease_rounds" -gt 0 ]
[ -n "$shape" ] && [ -n "$status" ] && [ -n "$state_dir" ]
best="$state_dir/checkpoints/gf2/$shape/best.txt"
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
cpu_failures=0
health=ok
if [ "${FAKE_METAFLIP_RECORD_SHAPE:-}" = "$shape" ]; then
  rank=$target
  producer_state=stopped
  wr_gap=-1
  wr_status=beats
  cpu_moves=101
  gpu_moves=24
fi
if [ "${FAKE_METAFLIP_LEASE_FAIL_SHAPE:-}" = "$shape" ]; then
  cpu_failures=1
  health=degraded
fi
if [ "${FAKE_METAFLIP_STALE_RECORD_SHAPE:-}" = "$shape" ]; then
  rank=$target
  producer_state=stopped
  wr_gap=-1
  wr_status=beats
fi
printf '%s\n1 1 1\n' "$rank" > "$best"
tmp="$status.tmp.$$"
printf 'schema=1 mode=rect-portfolio producer_state=%s sequence=1 epoch=0 elapsed=1 cpu_lanes=%s gpu_lanes=0 shapes=1 total_moves=%s total_cpu_moves=%s total_gpu_moves=%s health=%s\n' \
  "$producer_state" "$cpu_lanes" "$((cpu_moves + gpu_moves))" "$cpu_moves" "$gpu_moves" "$health" > "$tmp"
printf 'shape=%s ready=1 cpu=%s gpu=0 rank=%s bits=999 drops=0 density=0 moves=%s cpu_moves=%s gpu_moves=%s failures=%s cpu_failures=%s gpu_failures=0 mitm_failures=0 side_archive_loaded=1 side_archive_seeded=1 side_archive_saved=1 side_archive_rejects=0 side_archive_write_failures=0\n' \
  "$shape" "$cpu_lanes" "$rank" "$((cpu_moves + gpu_moves))" "$cpu_moves" "$gpu_moves" "$cpu_failures" "$cpu_failures" >> "$tmp"
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
stop_parent() {
  tmp="$status.tmp.stop.$$"
  if [ "${FAKE_METAFLIP_TERM_LEASE_FAIL_SHAPE:-}" = "$shape" ]; then
    sed -e '1s/producer_state=running/producer_state=stopped/' \
        -e '1s/health=ok/health=degraded/' \
        -e '2s/failures=0 cpu_failures=0/failures=1 cpu_failures=1/' \
        "$status" > "$tmp"
  else
    sed '1s/producer_state=running/producer_state=stopped/' "$status" > "$tmp"
  fi
  if [ "${FAKE_METAFLIP_TERM_MALFORMED_SHAPE:-}" = "$shape" ]; then
    printf 'shape=unexpected extra=1\n' >> "$tmp"
  fi
  mv -f "$tmp" "$status"
  if [ "${FAKE_METAFLIP_TERM_EXIT_SHAPE:-}" = "$shape" ]; then
    exit "${FAKE_METAFLIP_TERM_EXIT_CODE:-17}"
  fi
  exit 0
}
trap stop_parent TERM INT HUP
if [ "${FAKE_METAFLIP_REGRESS_MOVES_SHAPE:-}" = "$shape" ]; then
  # Leave enough time for the supervisor to observe the first cumulative
  # value, then atomically publish a fresh but regressed counter.
  sleep 2
  tmp="$status.tmp.regress.$$"
  sed '1s/total_moves=123/total_moves=122/' "$status" > "$tmp"
  mv -f "$tmp" "$status"
  while :; do
    touch "$status"
    sleep 1
  done
fi
if [ "${FAKE_METAFLIP_HUNG_LEASE_SHAPE:-}" = "$shape" ]; then
  # The parent heartbeat remains fresh while cumulative work is frozen,
  # modeling a live portfolio coordinator waiting on a wedged private child.
  while :; do
    touch "$status"
    sleep 1
  done
fi
if [ "${FAKE_METAFLIP_STALE_HEARTBEAT_SHAPE:-}" = "$shape" ]; then
  touch -t 200001010000 "$status"
fi
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

# Dry-run validates the complete parent/lease protocol without creating state or
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

parent_count=$(grep -c '^DRY_RUN parent=' "$DRY_OUTPUT" || true)
expect 'dry-run emits one parent per shape/node pair' test "$parent_count" -eq 2
expect 'node 0 is CPU- and memory-bound' grep -q -- '--cpunodebind=0 --membind=0' "$DRY_OUTPUT"
expect 'node 1 is CPU- and memory-bound' grep -q -- '--cpunodebind=1 --membind=1' "$DRY_OUTPUT"
expect 'explicit CPU walker and step budgets survive construction' grep -q -- '-J 3 --steps 77' "$DRY_OUTPUT"
expect 'parents are CPU-only, headless, and record-stopping' grep -q -- '--no-gpu --quiet --no-tui --stop-on-record' "$DRY_OUTPUT"
portfolio_count=$(grep -c -- '--rect --rect-shapes' "$DRY_OUTPUT" || true)
expect 'every command uses a single-shape portfolio parent' test "$portfolio_count" -eq 2
lease_count=$(grep -c -- '--rect-epoch-rounds 64' "$DRY_OUTPUT" || true)
expect 'every parent rotates finite 64-round leases by default' test "$lease_count" -eq 2
expect 'private child schedule is owned by each parent' sh -c '! grep -q -- "--rect-portfolio-child" "$1"' sh "$DRY_OUTPUT"
expect 'supervisor, not parents, owns the wall deadline' grep -q -- '--secs 0' "$DRY_OUTPUT"
expect 'parent epoch count cannot terminate a normal campaign' grep -q -- '--rounds 2000000000' "$DRY_OUTPUT"
expect 'durable archive is beside the standard checkpoint' grep -q -- 'best.txt.side-door-' "$DRY_OUTPUT"
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
  "${COMMON_ARGS[@]}" --shapes 2x3x4,3x4x4 --nodes 0,1 --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  proven_optimal_rc=0
else
  proven_optimal_rc=$?
fi
expect 'proven-optimal 2x3x4 is rejected from a strict-record campaign' test "$proven_optimal_rc" -eq 2
expect '2x3x4 rejection explains why no target exists' grep -q -- 'proven optimal at rank 20' "$INVALID_OUTPUT"

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

if supervisor_env "$VMSTAT_DRY" "$DRY_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" --lease-rounds 65 --dry-run \
  > "$INVALID_OUTPUT" 2>&1; then
  invalid_lease_rc=0
else
  invalid_lease_rc=$?
fi
expect 'lease widths above the runtime limit are rejected' test "$invalid_lease_rc" -eq 2
expect 'lease-width rejection reports the 1..64 contract' grep -q -- '--lease-rounds must be 1 through 64' "$INVALID_OUTPUT"

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
expect 'binary mismatch names the absent parent option' grep -q -- 'native binary does not advertise required rectangular option' "$INVALID_OUTPUT"
expect 'validation failures never invoke shutdown' test ! -e "$DRY_SHUTDOWN_LOG"

# Lock and orphan admission precede all legacy-state migration. Simulate a
# concurrently held lock and prove the old checkpoint is not copied.
LOCK_STATE="$TMP_ROOT/lock-state"
LOCK_LOG="$TMP_ROOT/lock-log"
LOCK_SHUTDOWN_LOG="$TMP_ROOT/lock-shutdown.log"
VMSTAT_LOCK="$TMP_ROOT/vmstat-lock"
mkdir -p "$LOCK_STATE/2x3x5"
printf '25\nlegacy locked\n' > "$LOCK_STATE/2x3x5/best.txt"
printf 'oom_kill 0\n' > "$VMSTAT_LOCK"
if FAKE_FLOCK_FAIL=1 supervisor_env "$VMSTAT_LOCK" "$LOCK_SHUTDOWN_LOG" \
  "${COMMON_ARGS[@]}" \
  --state-root "$LOCK_STATE" \
  --log-root "$LOCK_LOG" \
  --seconds 1 \
  --campaign-tag lock-test \
  > "$TMP_ROOT/lock.stdout" 2> "$TMP_ROOT/lock.stderr"; then
  lock_rc=0
else
  lock_rc=$?
fi
expect 'held supervisor lock rejects the campaign' test "$lock_rc" -eq 2
expect 'held lock prevents legacy checkpoint migration' test ! -e "$LOCK_STATE/2x3x5/checkpoints/gf2/2x3x5/best.txt"
expect 'held lock never invokes shutdown' test ! -e "$LOCK_SHUTDOWN_LOG"

# A deadline drains both parents, atomically publishes final status, and calls
# only the injected shutdown helper.
DEADLINE_STATE="$TMP_ROOT/deadline-state"
DEADLINE_LOG="$TMP_ROOT/deadline-log"
DEADLINE_SHUTDOWN_LOG="$TMP_ROOT/deadline-shutdown.log"
VMSTAT_DEADLINE="$TMP_ROOT/vmstat-deadline"
printf 'oom_kill 0\n' > "$VMSTAT_DEADLINE"
mkdir -p "$DEADLINE_STATE/2x3x5"
printf '25\nlegacy best\n' > "$DEADLINE_STATE/2x3x5/best.txt"
printf '26\nlegacy side door\n' > "$DEADLINE_STATE/2x3x5/best.txt.side-door-0.txt"
mkdir -p "$DEADLINE_STATE/2x3x5/checkpoints/gf2/2x3x5"
printf '26\nportfolio side wins\n' > "$DEADLINE_STATE/2x3x5/checkpoints/gf2/2x3x5/best.txt.side-door-1.txt"
printf '27\nlegacy side loses\n' > "$DEADLINE_STATE/2x3x5/best.txt.side-door-1.txt"
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
expect_token 'both parent heartbeats were aggregated' "$DEADLINE_STATUS" 'status_count=2'
expect_token 'final status has no running parents' "$DEADLINE_STATUS" 'running_count=0'
expect_token 'default lease width is explicit in cumulative status' "$DEADLINE_STATUS" 'lease_rounds=64'
expect_token 'clean leases have no cumulative failures' "$DEADLINE_STATUS" 'lease_failure_count=0'
expect_token 'both parents used the expected status protocol' "$DEADLINE_STATUS" 'protocol_error_count=0'
expect_token 'moves are summed across parents' "$DEADLINE_STATUS" 'total_moves=246'
expect 'per-shape objectives remain separate in aggregate status' grep -q -- 'best_by_shape=2x3x5:25:999,3x4x4:38:999' "$DEADLINE_STATUS"
expect 'legacy side-door archive is copied into the portfolio checkpoint layout' \
  grep -q -- 'legacy side door' "$DEADLINE_STATE/2x3x5/checkpoints/gf2/2x3x5/best.txt.side-door-0.txt"
expect 'existing portfolio side door wins over legacy migration' \
  grep -q -- 'portfolio side wins' "$DEADLINE_STATE/2x3x5/checkpoints/gf2/2x3x5/best.txt.side-door-1.txt"
shutdown_count=$(wc -l < "$DEADLINE_SHUTDOWN_LOG" | tr -d ' ')
expect 'deadline invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1
leftover_tmp=$(find "$DEADLINE_STATE/supervisor" -name '*.tmp.*' -print -quit)
expect 'atomic status/manifest replacement leaves no temp files' test -z "$leftover_tmp"

# A nominal deadline is only provisional. If TERM exposes a failed active
# lease, the post-drain audit must upgrade success to failure.
LATE_LEASE_STATE="$TMP_ROOT/late-lease-state"
LATE_LEASE_LOG="$TMP_ROOT/late-lease-log"
LATE_LEASE_SHUTDOWN_LOG="$TMP_ROOT/late-lease-shutdown.log"
VMSTAT_LATE_LEASE="$TMP_ROOT/vmstat-late-lease"
printf 'oom_kill 0\n' > "$VMSTAT_LATE_LEASE"
if env FAKE_METAFLIP_TERM_LEASE_FAIL_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_LATE_LEASE" METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$LATE_LEASE_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" --shapes 2x3x5 --nodes 0 \
  --state-root "$LATE_LEASE_STATE" --log-root "$LATE_LEASE_LOG" \
  --seconds 1 --campaign-tag late-lease-test \
  > "$TMP_ROOT/late-lease.stdout" 2> "$TMP_ROOT/late-lease.stderr"; then
  late_lease_rc=0
else
  late_lease_rc=$?
fi
LATE_LEASE_STATUS="$LATE_LEASE_STATE/supervisor/status.txt"
expect 'deadline drain exposing a lease failure returns failure' test "$late_lease_rc" -eq 70
expect_token 'late lease failure upgrades terminal state' "$LATE_LEASE_STATUS" 'producer_state=failed'
expect_token 'late lease failure replaces deadline reason' "$LATE_LEASE_STATUS" 'reason=lease-failure-count-1'

# The same terminal audit rejects a malformed final multiline snapshot.
LATE_BAD_STATE="$TMP_ROOT/late-bad-state"
LATE_BAD_LOG="$TMP_ROOT/late-bad-log"
LATE_BAD_SHUTDOWN_LOG="$TMP_ROOT/late-bad-shutdown.log"
VMSTAT_LATE_BAD="$TMP_ROOT/vmstat-late-bad"
printf 'oom_kill 0\n' > "$VMSTAT_LATE_BAD"
if env FAKE_METAFLIP_TERM_MALFORMED_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_LATE_BAD" METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$LATE_BAD_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" --shapes 2x3x5 --nodes 0 \
  --state-root "$LATE_BAD_STATE" --log-root "$LATE_BAD_LOG" \
  --seconds 1 --campaign-tag late-bad-test \
  > "$TMP_ROOT/late-bad.stdout" 2> "$TMP_ROOT/late-bad.stderr"; then
  late_bad_rc=0
else
  late_bad_rc=$?
fi
LATE_BAD_STATUS="$LATE_BAD_STATE/supervisor/status.txt"
expect 'deadline drain exposing malformed final status fails' test "$late_bad_rc" -eq 70
expect_token 'malformed final status upgrades terminal state' "$LATE_BAD_STATUS" 'producer_state=failed'
expect_token 'malformed final status replaces deadline reason' "$LATE_BAD_STATUS" 'reason=parent-protocol-error-count-1'

# A parent that acknowledges TERM with a nonzero exit cannot inherit the
# deadline's success code even when its final status is otherwise valid.
LATE_EXIT_STATE="$TMP_ROOT/late-exit-state"
LATE_EXIT_LOG="$TMP_ROOT/late-exit-log"
LATE_EXIT_SHUTDOWN_LOG="$TMP_ROOT/late-exit-shutdown.log"
VMSTAT_LATE_EXIT="$TMP_ROOT/vmstat-late-exit"
printf 'oom_kill 0\n' > "$VMSTAT_LATE_EXIT"
if env FAKE_METAFLIP_TERM_EXIT_SHAPE=2x3x5 FAKE_METAFLIP_TERM_EXIT_CODE=17 \
  PATH="$FAKE_TOOLS:$PATH" METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_LATE_EXIT" METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$LATE_EXIT_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" --shapes 2x3x5 --nodes 0 \
  --state-root "$LATE_EXIT_STATE" --log-root "$LATE_EXIT_LOG" \
  --seconds 1 --campaign-tag late-exit-test \
  > "$TMP_ROOT/late-exit.stdout" 2> "$TMP_ROOT/late-exit.stderr"; then
  late_exit_rc=0
else
  late_exit_rc=$?
fi
LATE_EXIT_STATUS="$LATE_EXIT_STATE/supervisor/status.txt"
expect 'deadline drain with nonzero parent exit returns failure' test "$late_exit_rc" -eq 70
expect_token 'late nonzero exit upgrades terminal state' "$LATE_EXIT_STATUS" 'producer_state=failed'
expect_token 'late nonzero exit replaces deadline reason' "$LATE_EXIT_STATUS" 'reason=parent-2x3x5-exit-17'

# A clean --stop-on-record parent exit is the one expected early-exit case. Its
# fresh production status and checkpoint must prove the objective before the
# sibling is drained.
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
expect 'verified record parent exit is successful' test "$record_rc" -eq 0
expect_token 'record terminal status is stopped' "$RECORD_STATUS" 'producer_state=stopped'
expect_token 'record reason names the winning shape' "$RECORD_STATUS" 'reason=record-2x3x5'
expect_token 'record drain leaves no sibling running' "$RECORD_STATUS" 'running_count=0'
expect 'record status retains the winning rank/density' grep -q -- 'best_by_shape=2x3x5:24:999' "$RECORD_STATUS"
record_rank=$(sed -n '1p' "$RECORD_STATE/2x3x5/checkpoints/gf2/2x3x5/best.txt")
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
expect_token 'stale-record exit remains an ordinary parent failure' "$STALE_STATUS" 'reason=parent-2x3x5-exit-0'
shutdown_count=$(wc -l < "$STALE_SHUTDOWN_LOG" | tr -d ' ')
expect 'stale record still invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# A private finite lease failure is cumulative parent telemetry. Even though
# the portfolio parent itself remains alive and could retry, the AWS campaign
# preserves the old fail-closed dead-child policy and drains every parent.
LEASE_FAIL_STATE="$TMP_ROOT/lease-fail-state"
LEASE_FAIL_LOG="$TMP_ROOT/lease-fail-log"
LEASE_FAIL_SHUTDOWN_LOG="$TMP_ROOT/lease-fail-shutdown.log"
VMSTAT_LEASE_FAIL="$TMP_ROOT/vmstat-lease-fail"
printf 'oom_kill 0\n' > "$VMSTAT_LEASE_FAIL"
if env FAKE_METAFLIP_LEASE_FAIL_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_LEASE_FAIL" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$LEASE_FAIL_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --state-root "$LEASE_FAIL_STATE" \
  --log-root "$LEASE_FAIL_LOG" \
  --seconds 20 \
  --campaign-tag lease-fail-test \
  > "$TMP_ROOT/lease-fail.stdout" 2> "$TMP_ROOT/lease-fail.stderr"; then
  lease_fail_rc=0
else
  lease_fail_rc=$?
fi
LEASE_FAIL_STATUS="$LEASE_FAIL_STATE/supervisor/status.txt"
expect 'failed private lease fails the supervisor' test "$lease_fail_rc" -eq 70
expect_token 'lease failure status is failed' "$LEASE_FAIL_STATUS" 'producer_state=failed'
expect_token 'lease failure reason is cumulative and durable' "$LEASE_FAIL_STATUS" 'reason=lease-failure-count-1'
expect_token 'lease failure count survives the drain' "$LEASE_FAIL_STATUS" 'lease_failure_count=1'
expect_token 'lease failure drain leaves no parent running' "$LEASE_FAIL_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$LEASE_FAIL_SHUTDOWN_LOG" | tr -d ' ')
expect 'lease failure invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# A responsive parent cannot mask a wedged private lease. The fixture keeps
# touching its valid parent status while total_moves remains frozen; monotone
# progress timeout, not heartbeat age, must drain it.
HUNG_STATE="$TMP_ROOT/hung-state"
HUNG_LOG="$TMP_ROOT/hung-log"
HUNG_SHUTDOWN_LOG="$TMP_ROOT/hung-shutdown.log"
VMSTAT_HUNG="$TMP_ROOT/vmstat-hung"
printf 'oom_kill 0\n' > "$VMSTAT_HUNG"
if env FAKE_METAFLIP_HUNG_LEASE_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_HUNG" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$HUNG_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --shapes 2x3x5 \
  --nodes 0 \
  --state-root "$HUNG_STATE" \
  --log-root "$HUNG_LOG" \
  --seconds 20 \
  --status-timeout 2 \
  --campaign-tag hung-lease-test \
  > "$TMP_ROOT/hung.stdout" 2> "$TMP_ROOT/hung.stderr"; then
  hung_rc=0
else
  hung_rc=$?
fi
HUNG_STATUS="$HUNG_STATE/supervisor/status.txt"
expect 'frozen private lease fails the supervisor' test "$hung_rc" -eq 70
expect_token 'frozen-progress status is failed' "$HUNG_STATUS" 'producer_state=failed'
expect_token 'frozen-progress reason is durable' "$HUNG_STATUS" 'reason=frozen-progress-count-1'
expect_token 'fresh parent heartbeat was not mislabeled stale' "$HUNG_STATUS" 'stale_count=0'
expect_token 'frozen-progress count survives the drain' "$HUNG_STATUS" 'progress_stale_count=1'
expect_token 'frozen-progress drain leaves no parent running' "$HUNG_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$HUNG_SHUTDOWN_LOG" | tr -d ' ')
expect 'frozen progress invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# A genuinely old parent heartbeat remains distinct from frozen work. This
# fixture leaves a valid snapshot untouched, so heartbeat age must win before
# the cumulative-progress timer reaches the same threshold.
STALE_HEARTBEAT_STATE="$TMP_ROOT/stale-heartbeat-state"
STALE_HEARTBEAT_LOG="$TMP_ROOT/stale-heartbeat-log"
STALE_HEARTBEAT_SHUTDOWN_LOG="$TMP_ROOT/stale-heartbeat-shutdown.log"
VMSTAT_STALE_HEARTBEAT="$TMP_ROOT/vmstat-stale-heartbeat"
printf 'oom_kill 0\n' > "$VMSTAT_STALE_HEARTBEAT"
if env FAKE_METAFLIP_STALE_HEARTBEAT_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_STALE_HEARTBEAT" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$STALE_HEARTBEAT_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --shapes 2x3x5 \
  --nodes 0 \
  --state-root "$STALE_HEARTBEAT_STATE" \
  --log-root "$STALE_HEARTBEAT_LOG" \
  --seconds 20 \
  --status-timeout 2 \
  --campaign-tag stale-heartbeat-test \
  > "$TMP_ROOT/stale-heartbeat.stdout" 2> "$TMP_ROOT/stale-heartbeat.stderr"; then
  stale_heartbeat_rc=0
else
  stale_heartbeat_rc=$?
fi
STALE_HEARTBEAT_STATUS="$STALE_HEARTBEAT_STATE/supervisor/status.txt"
expect 'old live parent heartbeat fails the supervisor' test "$stale_heartbeat_rc" -eq 70
expect_token 'stale-heartbeat status is failed' "$STALE_HEARTBEAT_STATUS" 'producer_state=failed'
expect_token 'stale-heartbeat reason is durable' "$STALE_HEARTBEAT_STATUS" 'reason=stale-heartbeat-count-1'
expect_token 'stale heartbeat is not mislabeled frozen progress' "$STALE_HEARTBEAT_STATUS" 'progress_stale_count=0'
expect_token 'stale-heartbeat drain leaves no parent running' "$STALE_HEARTBEAT_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$STALE_HEARTBEAT_SHUTDOWN_LOG" | tr -d ' ')
expect 'stale heartbeat invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# Cumulative work is a monotone protocol field. A fresh parent status that
# moves it backward is corruption/restart ambiguity, not renewed progress.
REGRESS_STATE="$TMP_ROOT/regress-state"
REGRESS_LOG="$TMP_ROOT/regress-log"
REGRESS_SHUTDOWN_LOG="$TMP_ROOT/regress-shutdown.log"
VMSTAT_REGRESS="$TMP_ROOT/vmstat-regress"
printf 'oom_kill 0\n' > "$VMSTAT_REGRESS"
if env FAKE_METAFLIP_REGRESS_MOVES_SHAPE=2x3x5 \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_REGRESS" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS" \
  FAKE_SHUTDOWN_LOG="$REGRESS_SHUTDOWN_LOG" \
  "$SUPERVISOR" "${COMMON_ARGS[@]}" \
  --shapes 2x3x5 \
  --nodes 0 \
  --state-root "$REGRESS_STATE" \
  --log-root "$REGRESS_LOG" \
  --seconds 20 \
  --campaign-tag regressed-counter-test \
  > "$TMP_ROOT/regress.stdout" 2> "$TMP_ROOT/regress.stderr"; then
  regress_rc=0
else
  regress_rc=$?
fi
REGRESS_STATUS="$REGRESS_STATE/supervisor/status.txt"
expect 'regressed cumulative moves fail the supervisor' test "$regress_rc" -eq 70
expect_token 'regressed-counter status is failed' "$REGRESS_STATUS" 'producer_state=failed'
expect_token 'regressed-counter reason is a protocol error' "$REGRESS_STATUS" 'reason=parent-protocol-error-count-1'
expect_token 'regressed-counter protocol count survives the drain' "$REGRESS_STATUS" 'protocol_error_count=1'
expect_token 'regressed-counter drain leaves no parent running' "$REGRESS_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$REGRESS_SHUTDOWN_LOG" | tr -d ' ')
expect 'regressed counter invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

# An arbitrary early parent exit is fail-closed: the sibling drains and the host
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
expect 'early parent exit fails the supervisor' test "$child_exit_rc" -eq 70
expect_token 'parent-exit status is failed' "$EXIT_STATUS" 'producer_state=failed'
expect_token 'parent-exit reason identifies shape and code' "$EXIT_STATUS" 'reason=parent-2x3x5-exit-17'
expect_token 'parent-exit drain leaves no sibling running' "$EXIT_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$EXIT_SHUTDOWN_LOG" | tr -d ' ')
expect 'parent exit invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

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
expect_token 'OOM drain leaves no parent running' "$OOM_STATUS" 'running_count=0'
shutdown_count=$(wc -l < "$OOM_SHUTDOWN_LOG" | tr -d ' ')
expect 'OOM invokes exactly the fake shutdown helper' test "$shutdown_count" -eq 1

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %d rectangular supervisor assertion(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: rectangular AWS/NUMA supervisor contract\n'
