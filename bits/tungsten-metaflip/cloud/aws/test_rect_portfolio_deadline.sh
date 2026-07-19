#!/usr/bin/env bash
# End-to-end regression for the AWS deadline -> parent TERM -> private lease
# cancellation path. Unlike test_supervise_rect_leaves.sh, this runs the real
# Tungsten portfolio parent and its real re-execed rectangular child.

set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
WORKSPACE_ROOT=$(CDPATH= cd -- "$PACKAGE_ROOT/../.." && pwd)
SUPERVISOR="$SCRIPT_DIR/supervise_rect_leaves.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-rect-deadline.XXXXXX")
SUPERVISOR_PID=""

cleanup() {
  local line token pid=""
  if [ -s "$TMP_ROOT/state/supervisor/pids.txt" ]; then
    while IFS= read -r line; do
      pid=""
      for token in $line; do
        case "$token" in pid=*) pid=${token#pid=} ;; esac
      done
      case "$pid" in
        ''|*[!0-9]*) ;;
        *)
          kill -TERM "$pid" 2>/dev/null || true
          kill -KILL "$pid" 2>/dev/null || true
          ;;
      esac
    done < "$TMP_ROOT/state/supervisor/pids.txt"
  fi
  if [ -n "$SUPERVISOR_PID" ]; then
    kill -TERM "$SUPERVISOR_PID" 2>/dev/null || true
    wait "$SUPERVISOR_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT INT TERM HUP

BINARY=${1:-}
if [ -z "$BINARY" ]; then
  TUNGSTEN=${TUNGSTEN:-"$WORKSPACE_ROOT/bin/tungsten"}
  [ -x "$TUNGSTEN" ] || {
    printf 'missing Tungsten compiler: %s\n' "$TUNGSTEN" >&2
    exit 2
  }
  BINARY="$TMP_ROOT/metaflip"
  "$TUNGSTEN" compile --release --native --lto --fast \
    "$PACKAGE_ROOT/bin/metaflip.w" --out "$BINARY"
fi
[ -x "$BINARY" ] || {
  printf 'Metaflip test binary is not executable: %s\n' "$BINARY" >&2
  exit 2
}

FAKE_TOOLS="$TMP_ROOT/tools"
NUMA_ROOT="$TMP_ROOT/numa"
VMSTAT_PATH="$TMP_ROOT/vmstat"
CGROUP_EVENTS_PATH="$TMP_ROOT/memory.events"
mkdir -p "$FAKE_TOOLS" "$NUMA_ROOT/node0"

# The production supervisor uses setsid and numactl. The wrappers retain its
# exact command and TERM fallback while keeping this regression portable to a
# non-NUMA developer machine.
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
chmod +x "$FAKE_TOOLS/setsid" "$FAKE_TOOLS/numactl" "$FAKE_TOOLS/flock"
printf 'oom_kill 0\n' > "$VMSTAT_PATH"
printf 'oom 0\noom_kill 0\n' > "$CGROUP_EVENTS_PATH"

STATE_ROOT="$TMP_ROOT/state"
LOG_ROOT="$TMP_ROOT/log"
STDOUT_PATH="$TMP_ROOT/supervisor.stdout"
STDERR_PATH="$TMP_ROOT/supervisor.stderr"
CAMPAIGN_TAG="deadline-real-$$"

set +e
env \
  PATH="$FAKE_TOOLS:$PATH" \
  METAFLIP_NUMA_ROOT="$NUMA_ROOT" \
  METAFLIP_VMSTAT_PATH="$VMSTAT_PATH" \
  METAFLIP_CGROUP_EVENTS_PATH="$CGROUP_EVENTS_PATH" \
  "$SUPERVISOR" \
    --binary "$BINARY" \
    --runtime-root "$PACKAGE_ROOT/lib/metaflip" \
    --state-root "$STATE_ROOT" \
    --log-root "$LOG_ROOT" \
    --shapes 2x3x5 \
    --nodes 0 \
    -J 1 \
    --steps 1000000000 \
    --lease-rounds 256 \
    --seconds 2 \
    --poll-seconds 1 \
    --drain-seconds 10 \
    --status-timeout 30 \
    --campaign-tag "$CAMPAIGN_TAG" \
    --no-shutdown \
    > "$STDOUT_PATH" 2> "$STDERR_PATH"
rc=$?
set -e

SUPERVISOR_STATUS="$STATE_ROOT/supervisor/status.txt"
PARENT_STATUS="$STATE_ROOT/2x3x5/status.txt"
if [ "$rc" -ne 0 ]; then
  printf 'deadline regression: supervisor exit=%s\n' "$rc" >&2
  sed -n '1,120p' "$STDERR_PATH" >&2
  sed -n '1,3p' "$SUPERVISOR_STATUS" >&2 2>/dev/null || true
  sed -n '1,3p' "$PARENT_STATUS" >&2 2>/dev/null || true
  exit 1
fi

require_token() {
  local label=$1 path=$2 token=$3
  if ! grep -Eq "(^| )${token}( |$)" "$path"; then
    printf 'deadline regression: missing %s (%s) in %s\n' "$token" "$label" "$path" >&2
    sed -n '1,3p' "$path" >&2 2>/dev/null || true
    exit 1
  fi
}

require_token 'supervisor terminal state' "$SUPERVISOR_STATUS" 'producer_state=stopped'
require_token 'supervisor deadline reason' "$SUPERVISOR_STATUS" 'reason=deadline'
require_token 'supervisor lease audit' "$SUPERVISOR_STATUS" 'lease_failure_count=0'
require_token 'supervisor protocol audit' "$SUPERVISOR_STATUS" 'protocol_error_count=0'
require_token 'supervisor drain' "$SUPERVISOR_STATUS" 'running_count=0'
require_token 'parent terminal state' "$PARENT_STATUS" 'producer_state=stopped'
require_token 'parent health' "$PARENT_STATUS" 'health=ok'
require_token 'cancelled lease aggregate' "$PARENT_STATUS" 'total_moves=0'
require_token 'cancelled lease failures' "$PARENT_STATUS" 'failures=0'
require_token 'cancelled CPU lease failures' "$PARENT_STATUS" 'cpu_failures=0'

parent_pid=$(awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^pid=/) { sub(/^pid=/, "", $i); print $i } }' "$STATE_ROOT/supervisor/pids.txt")
case "$parent_pid" in
  ''|*[!0-9]*)
    printf 'deadline regression: malformed parent PID manifest\n' >&2
    exit 1
    ;;
esac
if kill -0 "$parent_pid" 2>/dev/null; then
  printf 'deadline regression: parent PID %s survived terminal drain\n' "$parent_pid" >&2
  exit 1
fi

printf 'PASS real rectangular deadline cancellation remains healthy\n'
