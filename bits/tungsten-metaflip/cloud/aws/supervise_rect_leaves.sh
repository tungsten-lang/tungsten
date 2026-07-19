#!/usr/bin/env bash
# NUMA-local, fail-closed supervisor for independent rectangular Metaflip
# portfolio parents. The defaults map one selected rectangular profile to each
# NUMA node of an m8i.96xlarge. Each parent repeatedly leases its node to a
# finite private child, refreshing restart diversity at every exact boundary.
# The supervisor owns the wall deadline and, by default, shuts the AWS host
# down after every terminal campaign outcome so Spot spend stops.

set -Eeuo pipefail
set -f
export LC_ALL=C

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROGRAM=${0##*/}
BINARY=${METAFLIP_BINARY:-}
RUNTIME_INPUT=${METAFLIP_RUNTIME_ROOT:-"$PACKAGE_ROOT/lib/metaflip"}
STATE_ROOT=${METAFLIP_STATE_ROOT:-"${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/metaflip/rect-leaves"}
LOG_ROOT=${METAFLIP_LOG_ROOT:-}
LOG_ROOT_EXPLICIT=0

DURATION=7200
CAMPAIGN_TAG=""
SHAPES_CSV="3x3x4,3x4x4,2x3x5,3x4x5,4x5x5,5x6x7"
NODES_CSV="0,1,2,3,4,5"
WALKERS=64
STEPS=500000
LEASE_ROUNDS=16
POLL_SECONDS=2
DRAIN_SECONDS=120
STATUS_TIMEOUT=900
SHUTDOWN_ON_EXIT=1
SHUTDOWN_COMMAND=${METAFLIP_SHUTDOWN_COMMAND:-}
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: supervise_rect_leaves.sh --binary PATH [OPTIONS]

Launch one long-lived, CPU-only, single-shape rectangular portfolio parent per
NUMA node. Each parent rotates finite 16-round child leases by default. The
default six-parent campaign is the measured retarget for an m8i.96xlarge.

Required:
  --binary PATH              Native Metaflip coordinator executable

Campaign paths and lifetime:
  --runtime-root PATH        Package, lib, or lib/metaflip root
  --state-root PATH          Durable per-shape state and supervisor status
  --log-root PATH            Child logs (default: STATE_ROOT/log)
  --seconds N                Supervisor wall deadline; 0 means no deadline
  --campaign-tag TAG         Durable tag (default includes UTC time and PID)

Topology and work:
  --shapes CSV               Supported rectangular tensors, one per node
  --nodes CSV                Distinct NUMA nodes, one per shape
  -J, --walkers N            CPU walkers per parent/lease (default: 64)
  --steps N                  Moves per worker epoch (default: 500000)
  --lease-rounds N           Finite rounds per child lease (default: 16;
                             valid range: 1..64)

Health and host policy:
  --poll-seconds N           Supervisor heartbeat interval (default: 2)
  --drain-seconds N          TERM grace before KILL (default: 120)
  --status-timeout N         Fail on a stale parent heartbeat or frozen
                             cumulative lease progress (default: 900)
  --shutdown                 Shut the host down after drain (default)
  --no-shutdown              Leave the host running after drain
  --shutdown-command PATH    Invoke PATH with no arguments instead of the
                             default `sudo shutdown -h now` (testing hook)

Other:
  --dry-run                  Validate and print commands; write nothing
  -h, --help                 Show this help

Every NUMA process is an explicit one-shape rectangular portfolio parent. Its
finite children reuse the durable best/side-door archive and receive a fresh
nonce and door ticket from the portfolio scheduler on every lease. The
supervisor refuses square/unknown tensors, duplicate shapes or nodes, unequal
shape/node counts, and runtime/binary pairs missing the parent/private-child
protocol. An unexpected parent exit, failed child lease, stale heartbeat, or
observable kernel/cgroup OOM drains all parents. A clean parent exit is a
successful record stop only when its fresh final status and durable checkpoint
agree on a rank at or below the curated target. Supervisor status is atomically
replaced at:

  STATE_ROOT/supervisor/status.txt

WARNING: unless --no-shutdown is passed, a non-dry campaign requests host
shutdown after every terminal result, including a failed/OOM campaign.
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
    --campaign-tag)
      [ "$#" -ge 2 ] || die "--campaign-tag requires TAG"
      CAMPAIGN_TAG=$2
      shift 2
      ;;
    --shapes)
      [ "$#" -ge 2 ] || die "--shapes requires CSV"
      SHAPES_CSV=$2
      shift 2
      ;;
    --nodes)
      [ "$#" -ge 2 ] || die "--nodes requires CSV"
      NODES_CSV=$2
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
[ "$LEASE_ROUNDS" -ge 1 ] && [ "$LEASE_ROUNDS" -le 64 ] || \
  die "--lease-rounds must be 1 through 64"
[ "$POLL_SECONDS" -gt 0 ] || die "--poll-seconds must be positive"
[ "$DRAIN_SECONDS" -gt 0 ] || die "--drain-seconds must be positive"
[ "$STATUS_TIMEOUT" -gt 0 ] || die "--status-timeout must be positive"

case "$CAMPAIGN_TAG" in
  *[!A-Za-z0-9_.-]*) die "--campaign-tag may contain only letters, digits, '.', '_', and '-'" ;;
esac
if [ -z "$CAMPAIGN_TAG" ]; then
  CAMPAIGN_TAG="aws_rect_leaves_$(date -u +%Y%m%dT%H%M%SZ)_$$"
fi

[ -n "$STATE_ROOT" ] || die "--state-root may not be empty"
NEWLINE='
'
case "$STATE_ROOT" in *"$NEWLINE"*) die "--state-root may not contain a newline" ;; esac

[ -n "$BINARY" ] || die "--binary PATH is required (use a native release build)"
[ -x "$BINARY" ] || die "Metaflip binary is not executable: $BINARY"

normalize_runtime_root() {
  local candidate=$1 found=""
  if [ -f "$candidate/fleet.w" ]; then
    found=$candidate
  elif [ -f "$candidate/metaflip/fleet.w" ]; then
    found="$candidate/metaflip"
  elif [ -f "$candidate/lib/metaflip/fleet.w" ]; then
    found="$candidate/lib/metaflip"
  elif [ -f "$candidate/bits/tungsten-metaflip/lib/metaflip/fleet.w" ]; then
    found="$candidate/bits/tungsten-metaflip/lib/metaflip"
  else
    return 1
  fi
  (CDPATH= cd -- "$found" && pwd)
}

if ! RUNTIME_ROOT=$(normalize_runtime_root "$RUNTIME_INPUT"); then
  die "cannot locate lib/metaflip below runtime root: $RUNTIME_INPUT"
fi
if [ "$LOG_ROOT_EXPLICIT" -eq 0 ]; then
  LOG_ROOT="$STATE_ROOT/log"
fi
[ -n "$LOG_ROOT" ] || die "--log-root may not be empty"
case "$LOG_ROOT" in *"$NEWLINE"*) die "--log-root may not contain a newline" ;; esac

# The allowlist mirrors the strict-record subset of lib/metaflip/seeds/rect.w.
# Admission means the package has a checked-in exact frontier and an explicit
# lower target, not merely that the dimensions can be parsed by the worker.
supported_rect_shape() {
  case "$1" in
    2x2x5|2x2x6|2x2x7|2x2x8|2x2x9|2x3x5|2x4x5|2x5x6|\
    3x3x4|3x3x5|3x4x4|3x4x5|3x4x6|3x4x7|3x5x5|3x5x6|3x5x7|\
    4x4x5|4x4x6|4x5x5|4x5x6|4x5x7|4x5x8|4x6x6|4x6x7|4x6x8|5x6x7)
      return 0
      ;;
  esac
  return 1
}

# A clean portfolio parent exits early only for --stop-on-record. Keep the
# shell-side authorization independent of the parent's claim: its stopped
# status and durable checkpoint must agree at or below this curated target.
# The proven-optimal 2x3x4 profile is excluded from this strict-record
# campaign, so every admitted shape has one reachable rank-minus-one target.
rect_target_rank() {
  case "$1" in
    2x2x5) printf '17\n' ;;
    2x2x6) printf '20\n' ;;
    2x2x7) printf '24\n' ;;
    2x2x8) printf '27\n' ;;
    2x2x9) printf '31\n' ;;
    2x3x5) printf '24\n' ;;
    2x4x5) printf '32\n' ;;
    2x5x6) printf '46\n' ;;
    3x3x4) printf '28\n' ;;
    3x3x5) printf '35\n' ;;
    3x4x4) printf '37\n' ;;
    3x4x5) printf '46\n' ;;
    3x4x6) printf '53\n' ;;
    3x4x7) printf '63\n' ;;
    3x5x5) printf '57\n' ;;
    3x5x6) printf '67\n' ;;
    3x5x7) printf '78\n' ;;
    4x4x5) printf '59\n' ;;
    4x4x6) printf '72\n' ;;
    4x5x5) printf '75\n' ;;
    4x5x6) printf '89\n' ;;
    4x5x7) printf '103\n' ;;
    4x5x8) printf '117\n' ;;
    4x6x6) printf '104\n' ;;
    4x6x7) printf '122\n' ;;
    4x6x8) printf '139\n' ;;
    5x6x7) printf '149\n' ;;
    *) return 1 ;;
  esac
}

case "$SHAPES_CSV" in ''|,*|*,|*,,*) die "--shapes must be a non-empty CSV without empty entries" ;; esac
case "$NODES_CSV" in ''|,*|*,|*,,*) die "--nodes must be a non-empty CSV without empty entries" ;; esac

OLD_IFS=$IFS
IFS=,
SHAPES=( $SHAPES_CSV )
NODES=( $NODES_CSV )
IFS=$OLD_IFS

[ "${#SHAPES[@]}" -gt 0 ] || die "--shapes is empty"
[ "${#SHAPES[@]}" -eq "${#NODES[@]}" ] || \
  die "--shapes and --nodes need the same number of entries (${#SHAPES[@]} != ${#NODES[@]})"

index=0
while [ "$index" -lt "${#SHAPES[@]}" ]; do
  shape=${SHAPES[$index]}
  [ "$shape" != 2x3x4 ] || \
    die "rectangular shape '2x3x4' is proven optimal at rank 20 and has no strict record target"
  supported_rect_shape "$shape" || \
    die "unsupported rectangular shape '$shape' (square and uncurated tensors are not portfolio parents)"
  prior=0
  while [ "$prior" -lt "$index" ]; do
    [ "${SHAPES[$prior]}" != "$shape" ] || die "duplicate rectangular shape $shape"
    prior=$((prior + 1))
  done

  node=${NODES[$index]}
  require_uint --nodes "$node"
  prior=0
  while [ "$prior" -lt "$index" ]; do
    [ "${NODES[$prior]}" != "$node" ] || die "duplicate NUMA node $node"
    prior=$((prior + 1))
  done
  index=$((index + 1))
done

# A mismatched runtime and warm native binary can otherwise accept some of the
# constructed parent command and reject its private lease schedule only after
# spend begins. Require both parent and private-child markers on both sides
# before launching anything.
command -v strings >/dev/null 2>&1 || die "strings is required to validate the native binary"
for rect_option in --rect --rect-shapes --rect-epoch-rounds --rect-portfolio-child --rect-restart-nonce --rect-door-ticket; do
  grep -F -- "\"$rect_option\"" "$RUNTIME_ROOT/fleet.w" >/dev/null 2>&1 || \
    die "runtime does not advertise required rectangular option $rect_option"
  strings "$BINARY" 2>/dev/null | grep -F -- "$rect_option" >/dev/null || \
    die "native binary does not advertise required rectangular option $rect_option"
done

build_parent_command() {
  local child_index=$1 shape node shape_state best_path status_path archive_prefix tag
  shape=${SHAPES[$child_index]}
  node=${NODES[$child_index]}
  shape_state="$STATE_ROOT/$shape"
  best_path="$shape_state/checkpoints/gf2/$shape/best.txt"
  status_path="$shape_state/status.txt"
  archive_prefix="$best_path.side-door-"
  tag="${CAMPAIGN_TAG}_${shape}_n${node}"

  CHILD_COMMAND=(
    setsid numactl "--cpunodebind=$node" "--membind=$node"
    "$BINARY"
    --rect
    --rect-shapes "$shape"
    --rect-epoch-rounds "$LEASE_ROUNDS"
    --runtime-root "$RUNTIME_ROOT"
    --state-dir "$shape_state"
    --status "$status_path"
    --run-tag "$tag"
    -J "$WALKERS"
    --steps "$STEPS"
    --rounds 2000000000
    --secs 0
    --no-gpu
    --quiet
    --no-tui
    --stop-on-record
  )

  BUILT_SHAPE=$shape
  BUILT_NODE=$node
  BUILT_STATE=$shape_state
  BUILT_BEST=$best_path
  BUILT_STATUS=$status_path
  BUILT_ARCHIVE_PREFIX=$archive_prefix
  BUILT_LOG="$LOG_ROOT/$shape.log"
}

print_command() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'DRY_RUN campaign=%s parents=%d shapes=%s nodes=%s walkers=%d steps=%d lease_rounds=%d seconds=%d shutdown=%d\n' \
    "$CAMPAIGN_TAG" "${#SHAPES[@]}" "$SHAPES_CSV" "$NODES_CSV" "$WALKERS" "$STEPS" "$LEASE_ROUNDS" "$DURATION" "$SHUTDOWN_ON_EXIT"
  index=0
  while [ "$index" -lt "${#SHAPES[@]}" ]; do
    build_parent_command "$index"
    printf 'DRY_RUN parent=%s node=%s lease_rounds=%s state=%s best=%s status=%s archive_prefix=%s log=%s\n' \
      "$BUILT_SHAPE" "$BUILT_NODE" "$LEASE_ROUNDS" "$BUILT_STATE" \
      "$BUILT_BEST" "$BUILT_STATUS" "$BUILT_ARCHIVE_PREFIX" "$BUILT_LOG"
    print_command "${CHILD_COMMAND[@]}"
    index=$((index + 1))
  done
  if [ "$SHUTDOWN_ON_EXIT" -eq 1 ]; then
    if [ -n "$SHUTDOWN_COMMAND" ]; then
      printf 'DRY_RUN shutdown-command='
      print_command "$SHUTDOWN_COMMAND"
    else
      printf 'DRY_RUN shutdown-command=sudo shutdown -h now\n'
    fi
  fi
  exit 0
fi

command -v numactl >/dev/null 2>&1 || die "numactl is required"
command -v setsid >/dev/null 2>&1 || die "setsid is required"
command -v flock >/dev/null 2>&1 || die "flock is required"

NUMA_ROOT=${METAFLIP_NUMA_ROOT:-/sys/devices/system/node}
index=0
while [ "$index" -lt "${#NODES[@]}" ]; do
  node=${NODES[$index]}
  [ -d "$NUMA_ROOT/node$node" ] || die "NUMA node $node is not present below $NUMA_ROOT"
  index=$((index + 1))
done

if [ "$SHUTDOWN_ON_EXIT" -eq 1 ]; then
  if [ -n "$SHUTDOWN_COMMAND" ]; then
    [ -x "$SHUTDOWN_COMMAND" ] || die "shutdown command is not executable: $SHUTDOWN_COMMAND"
  else
    command -v shutdown >/dev/null 2>&1 || die "shutdown is required unless --no-shutdown is passed"
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null 2>&1 || die "sudo is required for host shutdown"
    fi
  fi
fi

mkdir -p "$STATE_ROOT/supervisor" "$LOG_ROOT"

# The previous launcher kept its checkpoint directly at SHAPE/best.txt. Move
# an immutable copy into the standard live-state layout on first use, together
# with any exact side-door slots. Existing portfolio state always wins.
copy_if_absent() {
  local source=$1 destination=$2 tmp
  [ -f "$source" ] || return 0
  [ ! -e "$destination" ] || return 0
  tmp="$destination.tmp.migrate.$$"
  cp -p -- "$source" "$tmp" || return 1
  if ln -- "$tmp" "$destination" 2>/dev/null; then
    rm -f -- "$tmp"
    return 0
  fi
  # link(2) is the no-clobber publication primitive. A destination created
  # after our first check wins; any other failure remains fatal.
  if [ -e "$destination" ]; then
    rm -f -- "$tmp"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

migrate_legacy_shape_state() {
  local shape=$1 legacy_best current_best slot legacy_side current_side
  legacy_best="$STATE_ROOT/$shape/best.txt"
  current_best="$STATE_ROOT/$shape/checkpoints/gf2/$shape/best.txt"
  mkdir -p "${current_best%/*}"
  copy_if_absent "$legacy_best" "$current_best" || return 1
  slot=0
  while [ "$slot" -lt 8 ]; do
    legacy_side="$legacy_best.side-door-$slot.txt"
    current_side="$current_best.side-door-$slot.txt"
    copy_if_absent "$legacy_side" "$current_side" || return 1
    slot=$((slot + 1))
  done
}

exec 9>"$STATE_ROOT/supervisor/lock"
if ! flock -n 9; then
  die "another supervisor holds $STATE_ROOT/supervisor/lock"
fi

PIDS=()
CHILD_SHAPES=()
CHILD_NODES=()
CHILD_BESTS=()
CHILD_STATUSES=()
CHILD_LOGS=()
CHILD_LAUNCH_EPOCHS=()
CHILD_REAPED=()
CHILD_EXIT_CODES=()
CHILD_PROGRESS_MOVES=()
CHILD_PROGRESS_EPOCHS=()
CHILD_PROGRESS_SEEN=()
LAUNCHED=0
CLEAN_EXIT=0
REQUESTED_REASON=""
SUPERVISOR_STATUS="$STATE_ROOT/supervisor/status.txt"
PIDS_PATH="$STATE_ROOT/supervisor/pids.txt"
STATUS_SEQUENCE=0
START_EPOCH=$(date +%s)
if [ "$DURATION" -gt 0 ]; then
  DEADLINE_EPOCH=$((START_EPOCH + DURATION))
else
  DEADLINE_EPOCH=0
fi

process_alive() {
  local pid=$1 stat_line rest state=""
  kill -0 "$pid" 2>/dev/null || return 1
  # kill -0 succeeds for an unreaped zombie. Prefer Linux /proc and retain a
  # portable ps fallback so the fake-process test also exercises early exits.
  if [ -r "/proc/$pid/stat" ]; then
    IFS= read -r stat_line < "/proc/$pid/stat" || return 1
    rest=${stat_line##*) }
    state=${rest%% *}
  else
    state=$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR == 1 { print substr($1, 1, 1) }')
  fi
  [ "$state" != Z ] || return 1
  return 0
}

terminate_groups() {
  local signal=$1 i=0 pid
  while [ "$i" -lt "$LAUNCHED" ]; do
    pid=${PIDS[$i]}
    if [ "${CHILD_REAPED[$i]}" -eq 0 ]; then
      # setsid makes pid the process-group leader in production. The direct
      # fallback is useful if setsid has already execed/exited or in tests.
      kill -"$signal" -- "-$pid" 2>/dev/null || kill -"$signal" "$pid" 2>/dev/null || true
    fi
    i=$((i + 1))
  done
}

request_host_shutdown() {
  if [ "$SHUTDOWN_ON_EXIT" -eq 0 ]; then
    return 0
  fi
  if [ -n "$SHUTDOWN_COMMAND" ]; then
    "$SHUTDOWN_COMMAND"
  elif [ "$(id -u)" -eq 0 ]; then
    shutdown -h now
  else
    sudo shutdown -h now
  fi
}

field_from_line() {
  local line=$1 wanted=$2 token
  for token in $line; do
    case "$token" in
      "$wanted"=*) printf '%s\n' "${token#*=}"; return 0 ;;
    esac
  done
  return 1
}

first_rank() {
  local path=$1 first
  [ -f "$path" ] || return 1
  first=$(sed -n '1p' "$path" 2>/dev/null || true)
  case "$first" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$first"
}

file_mtime() {
  local path=$1
  stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null
}

counter_from_file() {
  local path=$1 key=$2
  [ -r "$path" ] || { printf '0\n'; return 0; }
  awk -v wanted="$key" '$1 == wanted { print $2; found=1; exit } END { if (!found) print 0 }' "$path"
}

VMSTAT_PATH=${METAFLIP_VMSTAT_PATH:-/proc/vmstat}
CGROUP_EVENTS_PATH=${METAFLIP_CGROUP_EVENTS_PATH:-}
if [ -z "$CGROUP_EVENTS_PATH" ] && [ -r /proc/self/cgroup ] && [ -d /sys/fs/cgroup ]; then
  cgroup_relative=$(awk -F: '$1 == "0" { print $3; exit }' /proc/self/cgroup 2>/dev/null || true)
  if [ -n "$cgroup_relative" ] && [ -r "/sys/fs/cgroup${cgroup_relative}/memory.events" ]; then
    CGROUP_EVENTS_PATH="/sys/fs/cgroup${cgroup_relative}/memory.events"
  fi
fi
VM_OOM_BASE=$(counter_from_file "$VMSTAT_PATH" oom_kill)
CG_OOM_BASE=0
CG_OOM_KILL_BASE=0
if [ -n "$CGROUP_EVENTS_PATH" ]; then
  CG_OOM_BASE=$(counter_from_file "$CGROUP_EVENTS_PATH" oom)
  CG_OOM_KILL_BASE=$(counter_from_file "$CGROUP_EVENTS_PATH" oom_kill)
fi
VM_OOM_NOW=$VM_OOM_BASE
CG_OOM_NOW=$CG_OOM_BASE
CG_OOM_KILL_NOW=$CG_OOM_KILL_BASE

detect_system_oom() {
  VM_OOM_NOW=$(counter_from_file "$VMSTAT_PATH" oom_kill)
  if [ -n "$CGROUP_EVENTS_PATH" ]; then
    CG_OOM_NOW=$(counter_from_file "$CGROUP_EVENTS_PATH" oom)
    CG_OOM_KILL_NOW=$(counter_from_file "$CGROUP_EVENTS_PATH" oom_kill)
  fi
  if [ "$VM_OOM_NOW" -gt "$VM_OOM_BASE" ] \
     || [ "$CG_OOM_NOW" -gt "$CG_OOM_BASE" ] \
     || [ "$CG_OOM_KILL_NOW" -gt "$CG_OOM_KILL_BASE" ]; then
    return 0
  fi
  return 1
}

TOTAL_MOVES=0
RUNNING_COUNT=0
STATUS_COUNT=0
STALE_COUNT=0
LEASE_FAILURE_COUNT=0
PROTOCOL_ERROR_COUNT=0
PROGRESS_STALE_COUNT=0
BEST_BY_SHAPE="none"

SNAPSHOT_HEADER=""
SNAPSHOT_SHAPE=""

# Read one rename-stable inode exactly once, then split the required two-line
# parent protocol in memory. Reopening for the shape row could combine header
# generation N with row generation N+1 across an atomic replacement.
load_parent_snapshot() {
  local path=$1 body rest newline
  SNAPSHOT_HEADER=""
  SNAPSHOT_SHAPE=""
  [ -s "$path" ] || return 1
  body=$(< "$path") || return 1
  newline=$'\n'
  case "$body" in *"$newline"*) ;; *) return 1 ;; esac
  SNAPSHOT_HEADER=${body%%"$newline"*}
  rest=${body#*"$newline"}
  [ -n "$SNAPSHOT_HEADER" ] && [ -n "$rest" ] || return 1
  case "$rest" in *"$newline"*) return 1 ;; esac
  SNAPSHOT_SHAPE=$rest
  return 0
}

is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}

refresh_metrics() {
  local now=$1 i=0 line="" shape_line="" schema="" mode="" producer_state="" health="" shape_count="" sequence="" epoch="" reported_shape="" ready="" rank="" bits="" moves="" total_cpu_moves="" total_gpu_moves="" shape_moves="" cpu_moves="" gpu_moves="" failures="" lease_failures="" gpu_failures="" mitm_failures="" side_write_failures="" protocol_ok=1 mtime="" age="" summary=""
  TOTAL_MOVES=0
  RUNNING_COUNT=0
  STATUS_COUNT=0
  STALE_COUNT=0
  LEASE_FAILURE_COUNT=0
  PROTOCOL_ERROR_COUNT=0
  PROGRESS_STALE_COUNT=0
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ] && process_alive "${PIDS[$i]}"; then
      RUNNING_COUNT=$((RUNNING_COUNT + 1))
    fi
    rank=""
    bits=""
    moves=0
    if [ -s "${CHILD_STATUSES[$i]}" ]; then
      STATUS_COUNT=$((STATUS_COUNT + 1))
      line=""
      shape_line=""
      if load_parent_snapshot "${CHILD_STATUSES[$i]}"; then
        line=$SNAPSHOT_HEADER
        shape_line=$SNAPSHOT_SHAPE
      fi
      if [ -n "$line" ] && [ -n "$shape_line" ]; then
        schema=$(field_from_line "$line" schema || true)
        mode=$(field_from_line "$line" mode || true)
        producer_state=$(field_from_line "$line" producer_state || true)
        health=$(field_from_line "$line" health || true)
        shape_count=$(field_from_line "$line" shapes || true)
        sequence=$(field_from_line "$line" sequence || true)
        epoch=$(field_from_line "$line" epoch || true)
        reported_shape=$(field_from_line "$shape_line" shape || true)
        ready=$(field_from_line "$shape_line" ready || true)
        rank=$(field_from_line "$shape_line" rank || true)
        bits=$(field_from_line "$shape_line" bits || true)
        moves=$(field_from_line "$line" total_moves || true)
        total_cpu_moves=$(field_from_line "$line" total_cpu_moves || true)
        total_gpu_moves=$(field_from_line "$line" total_gpu_moves || true)
        shape_moves=$(field_from_line "$shape_line" moves || true)
        cpu_moves=$(field_from_line "$shape_line" cpu_moves || true)
        gpu_moves=$(field_from_line "$shape_line" gpu_moves || true)
        failures=$(field_from_line "$shape_line" failures || true)
        lease_failures=$(field_from_line "$shape_line" cpu_failures || true)
        gpu_failures=$(field_from_line "$shape_line" gpu_failures || true)
        mitm_failures=$(field_from_line "$shape_line" mitm_failures || true)
        side_write_failures=$(field_from_line "$shape_line" side_archive_write_failures || true)
        protocol_ok=1
        [ "$schema" = 1 ] || protocol_ok=0
        [ "$mode" = rect-portfolio ] || protocol_ok=0
        [ "$health" = ok ] || protocol_ok=0
        [ "$shape_count" = 1 ] || protocol_ok=0
        case "$producer_state" in running|stopped) ;; *) protocol_ok=0 ;; esac
        for numeric in "$sequence" "$epoch" "$rank" "$bits" "$moves" "$total_cpu_moves" "$total_gpu_moves" "$shape_moves" "$cpu_moves" "$gpu_moves" "$failures" "$lease_failures" "$gpu_failures" "$mitm_failures" "$side_write_failures"; do
          is_uint "$numeric" || protocol_ok=0
        done
        [ "$ready" = 1 ] || protocol_ok=0
        if is_uint "$rank"; then [ "$rank" -gt 0 ] || protocol_ok=0; fi
        if ! is_uint "$lease_failures"; then lease_failures=0; fi
        LEASE_FAILURE_COUNT=$((LEASE_FAILURE_COUNT + lease_failures))
        [ "$reported_shape" = "${CHILD_SHAPES[$i]}" ] || protocol_ok=0
        if is_uint "$moves" && is_uint "$total_cpu_moves" && is_uint "$total_gpu_moves"; then
          [ "$moves" -eq $((total_cpu_moves + total_gpu_moves)) ] || protocol_ok=0
        fi
        if is_uint "$shape_moves" && is_uint "$cpu_moves" && is_uint "$gpu_moves"; then
          [ "$shape_moves" -eq $((cpu_moves + gpu_moves)) ] || protocol_ok=0
        fi
        if is_uint "$moves" && is_uint "$shape_moves"; then [ "$moves" -eq "$shape_moves" ] || protocol_ok=0; fi
        if is_uint "$total_cpu_moves" && is_uint "$cpu_moves"; then [ "$total_cpu_moves" -eq "$cpu_moves" ] || protocol_ok=0; fi
        if is_uint "$total_gpu_moves" && is_uint "$gpu_moves"; then [ "$total_gpu_moves" -eq "$gpu_moves" ] || protocol_ok=0; fi
        if is_uint "$failures" && is_uint "$lease_failures" && is_uint "$gpu_failures" && is_uint "$mitm_failures"; then
          [ "$failures" -eq $((lease_failures + gpu_failures + mitm_failures)) ] || protocol_ok=0
          [ "$failures" -eq 0 ] || protocol_ok=0
        fi
        if is_uint "$side_write_failures"; then [ "$side_write_failures" -eq 0 ] || protocol_ok=0; fi
        case "$moves" in
          ''|*[!0-9]*) ;;
          *)
            if [ "${CHILD_PROGRESS_SEEN[$i]}" -eq 0 ]; then
              CHILD_PROGRESS_SEEN[$i]=1
              CHILD_PROGRESS_MOVES[$i]=$moves
              # A first heartbeat with no completed work is not progress.
              # Preserve the launch epoch so a late zero-work snapshot cannot
              # buy the wedged lease a second full timeout window.
              if [ "$moves" -gt 0 ]; then
                CHILD_PROGRESS_EPOCHS[$i]=$now
              fi
            elif [ "$moves" -lt "${CHILD_PROGRESS_MOVES[$i]}" ]; then
              protocol_ok=0
            elif [ "$moves" -gt "${CHILD_PROGRESS_MOVES[$i]}" ]; then
              CHILD_PROGRESS_MOVES[$i]=$moves
              CHILD_PROGRESS_EPOCHS[$i]=$now
            fi
            ;;
        esac
        [ "$protocol_ok" -eq 1 ] || PROTOCOL_ERROR_COUNT=$((PROTOCOL_ERROR_COUNT + 1))
      else
        # The launched command is always a portfolio parent; a missing second
        # row, extra row, or other malformed snapshot is terminal protocol
        # failure. Best-path fallback below keeps diagnostics useful.
        moves=0
        PROTOCOL_ERROR_COUNT=$((PROTOCOL_ERROR_COUNT + 1))
      fi
      is_uint "$moves" || moves=0
      TOTAL_MOVES=$((TOTAL_MOVES + moves))
      mtime=$(file_mtime "${CHILD_STATUSES[$i]}" || true)
      case "$mtime" in ''|*[!0-9]*) mtime=$now ;; esac
      age=$((now - mtime))
      [ "$age" -le "$STATUS_TIMEOUT" ] || STALE_COUNT=$((STALE_COUNT + 1))
    elif [ $((now - START_EPOCH)) -gt "$STATUS_TIMEOUT" ]; then
      STALE_COUNT=$((STALE_COUNT + 1))
    fi
    if [ "${CHILD_PROGRESS_SEEN[$i]}" -ne 0 ] \
       && [ $((now - CHILD_PROGRESS_EPOCHS[$i])) -gt "$STATUS_TIMEOUT" ]; then
      PROGRESS_STALE_COUNT=$((PROGRESS_STALE_COUNT + 1))
    fi
    case "$rank" in ''|*[!0-9]*) rank=$(first_rank "${CHILD_BESTS[$i]}" || true) ;; esac
    case "$rank" in ''|*[!0-9]*) rank=0 ;; esac
    case "$bits" in ''|*[!0-9]*) bits=0 ;; esac
    if [ -n "$summary" ]; then summary="$summary,"; fi
    summary="${summary}${CHILD_SHAPES[$i]}:${rank}:${bits}"
    i=$((i + 1))
  done
  if [ -n "$summary" ]; then BEST_BY_SHAPE=$summary; else BEST_BY_SHAPE=none; fi
}

write_supervisor_status() {
  local producer_state=$1 reason=$2 now elapsed tmp
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  STATUS_SEQUENCE=$((STATUS_SEQUENCE + 1))
  tmp="$SUPERVISOR_STATUS.tmp.$$.$STATUS_SEQUENCE"
  printf '%s\n' \
    "schema=1 producer_state=$producer_state updated_epoch=$now sequence=$STATUS_SEQUENCE campaign=$CAMPAIGN_TAG elapsed=$elapsed deadline_epoch=$DEADLINE_EPOCH shape_count=${#SHAPES[@]} launched_count=$LAUNCHED running_count=$RUNNING_COUNT status_count=$STATUS_COUNT stale_count=$STALE_COUNT progress_stale_count=$PROGRESS_STALE_COUNT lease_rounds=$LEASE_ROUNDS lease_failure_count=$LEASE_FAILURE_COUNT protocol_error_count=$PROTOCOL_ERROR_COUNT total_moves=$TOTAL_MOVES shapes=$SHAPES_CSV nodes=$NODES_CSV best_by_shape=$BEST_BY_SHAPE oom_vm=$VM_OOM_NOW oom_cgroup=$CG_OOM_NOW oom_kill_cgroup=$CG_OOM_KILL_NOW reason=$reason" \
    > "$tmp"
  mv -f -- "$tmp" "$SUPERVISOR_STATUS"
}

write_pid_manifest() {
  local tmp="$PIDS_PATH.tmp.$$" i=0
  : > "$tmp"
  while [ "$i" -lt "$LAUNCHED" ]; do
    printf 'shape=%s pid=%s node=%s lease_rounds=%s best=%s status=%s log=%s\n' \
      "${CHILD_SHAPES[$i]}" "${PIDS[$i]}" "${CHILD_NODES[$i]}" "$LEASE_ROUNDS" \
      "${CHILD_BESTS[$i]}" "${CHILD_STATUSES[$i]}" "${CHILD_LOGS[$i]}" >> "$tmp"
    i=$((i + 1))
  done
  mv -f -- "$tmp" "$PIDS_PATH"
}

reap_child() {
  local child_index=$1 rc
  if [ "${CHILD_REAPED[$child_index]}" -eq 1 ]; then
    REAP_RC=${CHILD_EXIT_CODES[$child_index]}
    return 0
  fi
  if wait "${PIDS[$child_index]}"; then rc=0; else rc=$?; fi
  CHILD_REAPED[$child_index]=1
  CHILD_EXIT_CODES[$child_index]=$rc
  REAP_RC=$rc
}

record_stop_from_status() {
  local child_index=$1 line shape_line schema mode producer_state health shape_count tensor rank bits moves shape_moves cpu_moves gpu_moves failures lease_failures gpu_failures mitm_failures side_write_failures target checkpoint_rank mtime
  [ -s "${CHILD_STATUSES[$child_index]}" ] || return 1
  mtime=$(file_mtime "${CHILD_STATUSES[$child_index]}" || true)
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  [ "$mtime" -ge "${CHILD_LAUNCH_EPOCHS[$child_index]}" ] || return 1
  load_parent_snapshot "${CHILD_STATUSES[$child_index]}" || return 1
  line=$SNAPSHOT_HEADER
  shape_line=$SNAPSHOT_SHAPE
  schema=$(field_from_line "$line" schema || true)
  mode=$(field_from_line "$line" mode || true)
  producer_state=$(field_from_line "$line" producer_state || true)
  health=$(field_from_line "$line" health || true)
  shape_count=$(field_from_line "$line" shapes || true)
  moves=$(field_from_line "$line" total_moves || true)
  [ "$schema" = 1 ] || return 1
  [ "$mode" = rect-portfolio ] || return 1
  [ "$health" = ok ] || return 1
  [ "$shape_count" = 1 ] || return 1
  tensor=$(field_from_line "$shape_line" shape || true)
  rank=$(field_from_line "$shape_line" rank || true)
  bits=$(field_from_line "$shape_line" bits || true)
  shape_moves=$(field_from_line "$shape_line" moves || true)
  cpu_moves=$(field_from_line "$shape_line" cpu_moves || true)
  gpu_moves=$(field_from_line "$shape_line" gpu_moves || true)
  failures=$(field_from_line "$shape_line" failures || true)
  lease_failures=$(field_from_line "$shape_line" cpu_failures || true)
  gpu_failures=$(field_from_line "$shape_line" gpu_failures || true)
  mitm_failures=$(field_from_line "$shape_line" mitm_failures || true)
  side_write_failures=$(field_from_line "$shape_line" side_archive_write_failures || true)
  [ "$tensor" = "${CHILD_SHAPES[$child_index]}" ] || return 1
  [ "$producer_state" = stopped ] || return 1
  for numeric in "$rank" "$bits" "$moves" "$shape_moves" "$cpu_moves" "$gpu_moves" "$failures" "$lease_failures" "$gpu_failures" "$mitm_failures" "$side_write_failures"; do
    is_uint "$numeric" || return 1
  done
  [ "$moves" -eq "$shape_moves" ] || return 1
  [ "$shape_moves" -eq $((cpu_moves + gpu_moves)) ] || return 1
  [ "$failures" -eq $((lease_failures + gpu_failures + mitm_failures)) ] || return 1
  [ "$failures" -eq 0 ] || return 1
  [ "$side_write_failures" -eq 0 ] || return 1
  [ "$rank" -gt 0 ] || return 1
  checkpoint_rank=$(first_rank "${CHILD_BESTS[$child_index]}" || true)
  [ "$checkpoint_rank" = "$rank" ] || return 1
  target=$(rect_target_rank "$tensor" || true)
  case "$target" in ''|*[!0-9]*) return 1 ;; esac
  [ "$target" -gt 0 ] && [ "$rank" -le "$target" ]
}

unexpected_parent_exit() {
  local i=0 rc log
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ] && ! process_alive "${PIDS[$i]}"; then
      reap_child "$i"
      rc=$REAP_RC
      log=${CHILD_LOGS[$i]}
      if [ "$rc" -eq 0 ] && record_stop_from_status "$i"; then
        CHILD_EXIT_REASON="record-${CHILD_SHAPES[$i]}"
      elif [ "$rc" -eq 137 ] || [ "$rc" -eq 9 ] \
         || grep -Eiq 'out of memory|oom-kill|oom killer|cannot allocate memory|std::bad_alloc|Killed process' "$log" 2>/dev/null; then
        CHILD_EXIT_REASON="oom-parent-${CHILD_SHAPES[$i]}-exit-$rc"
      else
        CHILD_EXIT_REASON="parent-${CHILD_SHAPES[$i]}-exit-$rc"
      fi
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

drain_all() {
  local reason=$1 drain_deadline now i
  refresh_metrics "$(date +%s)"
  write_supervisor_status draining "$reason"
  terminate_groups TERM
  drain_deadline=$(( $(date +%s) + DRAIN_SECONDS ))
  while :; do
    now=$(date +%s)
    refresh_metrics "$now"
    write_supervisor_status draining "$reason"
    [ "$RUNNING_COUNT" -gt 0 ] || break
    [ "$now" -lt "$drain_deadline" ] || break
    sleep "$POLL_SECONDS" || true
  done
  if [ "$RUNNING_COUNT" -gt 0 ]; then
    printf '%s: drain grace expired; KILLing %d remaining parent/parents\n' "$PROGRAM" "$RUNNING_COUNT" >&2
    terminate_groups KILL
  fi
  i=0
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ]; then
      reap_child "$i"
    fi
    i=$((i + 1))
  done
  refresh_metrics "$(date +%s)"
}

audit_terminal_statuses() {
  local i=0 errors=0 line producer_state mtime
  while [ "$i" -lt "$LAUNCHED" ]; do
    if ! load_parent_snapshot "${CHILD_STATUSES[$i]}"; then
      errors=$((errors + 1))
    else
      line=$SNAPSHOT_HEADER
      producer_state=$(field_from_line "$line" producer_state || true)
      mtime=$(file_mtime "${CHILD_STATUSES[$i]}" || true)
      if [ "$producer_state" != stopped ]; then
        errors=$((errors + 1))
      elif ! is_uint "$mtime" || [ "$mtime" -lt "${CHILD_LAUNCH_EPOCHS[$i]}" ]; then
        errors=$((errors + 1))
      fi
    fi
    i=$((i + 1))
  done
  if [ "$errors" -gt "$PROTOCOL_ERROR_COUNT" ]; then
    PROTOCOL_ERROR_COUNT=$errors
  fi
}

terminal_exit_failure() {
  local i=0 rc log
  while [ "$i" -lt "$LAUNCHED" ]; do
    rc=${CHILD_EXIT_CODES[$i]}
    if [ "$rc" -ne 0 ]; then
      log=${CHILD_LOGS[$i]}
      if [ "$rc" -eq 137 ] || [ "$rc" -eq 9 ] \
         || grep -Eiq 'out of memory|oom-kill|oom killer|cannot allocate memory|std::bad_alloc|Killed process' "$log" 2>/dev/null; then
        TERMINAL_AUDIT_REASON="oom-parent-${CHILD_SHAPES[$i]}-exit-$rc"
      else
        TERMINAL_AUDIT_REASON="parent-${CHILD_SHAPES[$i]}-exit-$rc"
      fi
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

audit_terminal_outcome() {
  TERMINAL_AUDIT_REASON=""
  # drain_all has reaped every parent and refreshed its final snapshot.
  audit_terminal_statuses
  if detect_system_oom; then
    TERMINAL_AUDIT_REASON=oom-counter-increased
  elif [ "$LEASE_FAILURE_COUNT" -gt 0 ]; then
    TERMINAL_AUDIT_REASON="lease-failure-count-$LEASE_FAILURE_COUNT"
  elif [ "$PROTOCOL_ERROR_COUNT" -gt 0 ]; then
    TERMINAL_AUDIT_REASON="parent-protocol-error-count-$PROTOCOL_ERROR_COUNT"
  elif [ "$PROGRESS_STALE_COUNT" -gt 0 ]; then
    TERMINAL_AUDIT_REASON="frozen-progress-count-$PROGRESS_STALE_COUNT"
  elif [ "$STALE_COUNT" -gt 0 ]; then
    TERMINAL_AUDIT_REASON="stale-heartbeat-count-$STALE_COUNT"
  else
    terminal_exit_failure || true
  fi
  [ -z "$TERMINAL_AUDIT_REASON" ] || return 1
  return 0
}

emergency_cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$CLEAN_EXIT" -eq 0 ] && [ "$LAUNCHED" -gt 0 ]; then
    printf '%s: emergency fail-closed drain of %d launched parents\n' "$PROGRAM" "$LAUNCHED" >&2
    terminate_groups TERM
    sleep 2
    terminate_groups KILL
    i=0
    while [ "$i" -lt "$LAUNCHED" ]; do
      wait "${PIDS[$i]}" 2>/dev/null
      i=$((i + 1))
    done
    refresh_metrics "$(date +%s)"
    write_supervisor_status failed "supervisor-error-$rc"
    request_host_shutdown
  fi
  exit "$rc"
}

trap emergency_cleanup EXIT
trap 'REQUESTED_REASON=signal-int' INT
trap 'REQUESTED_REASON=signal-term' TERM
trap 'REQUESTED_REASON=signal-hup' HUP

# Refuse to duplicate an orphaned campaign after a supervisor SIGKILL.
if [ -s "$PIDS_PATH" ]; then
  while IFS= read -r prior_line; do
    prior_pid=""
    for prior_token in $prior_line; do
      case "$prior_token" in pid=*) prior_pid=${prior_token#pid=} ;; esac
    done
    case "$prior_pid" in ''|*[!0-9]*) continue ;; esac
    if kill -0 "$prior_pid" 2>/dev/null && [ -r "/proc/$prior_pid/cmdline" ] \
       && tr '\000' ' ' < "/proc/$prior_pid/cmdline" | grep -F -- "$STATE_ROOT/" >/dev/null; then
      die "prior parent PID $prior_pid is still live; inspect $PIDS_PATH before restarting"
    fi
  done < "$PIDS_PATH"
fi

# Only the exclusive supervisor may migrate durable state, and a manifested
# live orphan is rejected before any destination is created.
index=0
while [ "$index" -lt "${#SHAPES[@]}" ]; do
  mkdir -p "$STATE_ROOT/${SHAPES[$index]}"
  migrate_legacy_shape_state "${SHAPES[$index]}" || \
    die "could not migrate durable state for ${SHAPES[$index]}"
  index=$((index + 1))
done

index=0
while [ "$index" -lt "${#SHAPES[@]}" ]; do
  build_parent_command "$index"
  if [ -e "$BUILT_STATUS" ]; then
    mv -f -- "$BUILT_STATUS" "$BUILT_STATUS.previous.$CAMPAIGN_TAG"
  fi
  if [ -e "$BUILT_LOG" ]; then
    mv -f -- "$BUILT_LOG" "$BUILT_LOG.previous.$CAMPAIGN_TAG"
  fi
  : > "$BUILT_LOG"

  child_launch_epoch=$(date +%s)
  "${CHILD_COMMAND[@]}" 9>&- >> "$BUILT_LOG" 2>&1 &
  pid=$!
  PIDS[$LAUNCHED]=$pid
  CHILD_SHAPES[$LAUNCHED]=$BUILT_SHAPE
  CHILD_NODES[$LAUNCHED]=$BUILT_NODE
  CHILD_BESTS[$LAUNCHED]=$BUILT_BEST
  CHILD_STATUSES[$LAUNCHED]=$BUILT_STATUS
  CHILD_LOGS[$LAUNCHED]=$BUILT_LOG
  CHILD_LAUNCH_EPOCHS[$LAUNCHED]=$child_launch_epoch
  CHILD_REAPED[$LAUNCHED]=0
  CHILD_EXIT_CODES[$LAUNCHED]=-1
  CHILD_PROGRESS_MOVES[$LAUNCHED]=0
  CHILD_PROGRESS_EPOCHS[$LAUNCHED]=$child_launch_epoch
  CHILD_PROGRESS_SEEN[$LAUNCHED]=0
  LAUNCHED=$((LAUNCHED + 1))
  write_pid_manifest
  printf '%s: launched parent %s pid=%s node=%s J=%s steps=%s lease_rounds=%s\n' \
    "$PROGRAM" "$BUILT_SHAPE" "$pid" "$BUILT_NODE" "$WALKERS" "$STEPS" "$LEASE_ROUNDS" >&2

  if [ -n "$REQUESTED_REASON" ]; then
    drain_all "$REQUESTED_REASON"
    launch_terminal_reason=$REQUESTED_REASON
    launch_terminal_state=stopped
    CLEAN_EXIT=1
    trap - EXIT INT TERM HUP
    signal_exit=0
    [ "$REQUESTED_REASON" != signal-int ] || signal_exit=130
    if ! audit_terminal_outcome; then
      launch_terminal_reason=$TERMINAL_AUDIT_REASON
      launch_terminal_state=failed
      signal_exit=70
      case "$launch_terminal_reason" in oom-*) signal_exit=71 ;; esac
    fi
    write_supervisor_status "$launch_terminal_state" "$launch_terminal_reason"
    if request_host_shutdown; then
      exit "$signal_exit"
    else
      shutdown_rc=$?
      write_supervisor_status failed "shutdown-command-failed-$shutdown_rc"
      exit 72
    fi
  fi
  index=$((index + 1))
done

[ "$LAUNCHED" -eq "${#SHAPES[@]}" ] || die "launched $LAUNCHED of ${#SHAPES[@]} parents"

CHILD_EXIT_REASON=""
FINAL_REASON=""
printf '%s: campaign %s running %d parents across nodes %s; status %s\n' \
  "$PROGRAM" "$CAMPAIGN_TAG" "$LAUNCHED" "$NODES_CSV" "$SUPERVISOR_STATUS" >&2

while :; do
  now=$(date +%s)
  refresh_metrics "$now"

  if detect_system_oom; then
    FINAL_REASON=oom-counter-increased
  elif unexpected_parent_exit; then
    FINAL_REASON=$CHILD_EXIT_REASON
  elif [ "$LEASE_FAILURE_COUNT" -gt 0 ]; then
    FINAL_REASON="lease-failure-count-$LEASE_FAILURE_COUNT"
  elif [ "$PROTOCOL_ERROR_COUNT" -gt 0 ]; then
    FINAL_REASON="parent-protocol-error-count-$PROTOCOL_ERROR_COUNT"
  elif [ "$PROGRESS_STALE_COUNT" -gt 0 ]; then
    FINAL_REASON="frozen-progress-count-$PROGRESS_STALE_COUNT"
  elif [ "$STALE_COUNT" -gt 0 ]; then
    FINAL_REASON="stale-heartbeat-count-$STALE_COUNT"
  elif [ -n "$REQUESTED_REASON" ]; then
    FINAL_REASON=$REQUESTED_REASON
  elif [ "$DURATION" -gt 0 ] && [ "$now" -ge "$DEADLINE_EPOCH" ]; then
    FINAL_REASON=deadline
  fi

  write_supervisor_status running "${FINAL_REASON:-none}"
  [ -z "$FINAL_REASON" ] || break
  sleep "$POLL_SECONDS" || true
done

drain_all "$FINAL_REASON"

# A nominal deadline/record/signal is not successful until the drain itself is
# audited. Cancellation may expose an OOM, failed lease, malformed final
# snapshot, stale/frozen work, or nonzero parent exit that was not observable
# when the terminal request was chosen.
case "$FINAL_REASON" in
  deadline|record-*|signal-int|signal-term|signal-hup)
    if ! audit_terminal_outcome; then
      FINAL_REASON=$TERMINAL_AUDIT_REASON
    fi
    ;;
esac

FINAL_STATE=failed
EXIT_CODE=70
case "$FINAL_REASON" in
  record-*)
    FINAL_STATE=stopped
    EXIT_CODE=0
    ;;
  deadline)
    FINAL_STATE=stopped
    EXIT_CODE=0
    ;;
  signal-int)
    FINAL_STATE=stopped
    EXIT_CODE=130
    ;;
  signal-term|signal-hup)
    FINAL_STATE=stopped
    EXIT_CODE=0
    ;;
  oom-*)
    FINAL_STATE=failed
    EXIT_CODE=71
    ;;
  *)
    FINAL_STATE=failed
    EXIT_CODE=70
    ;;
esac

write_supervisor_status "$FINAL_STATE" "$FINAL_REASON"
printf '%s: campaign %s state=%s reason=%s total_moves=%s best_by_shape=%s\n' \
  "$PROGRAM" "$CAMPAIGN_TAG" "$FINAL_STATE" "$FINAL_REASON" "$TOTAL_MOVES" "$BEST_BY_SHAPE" >&2

CLEAN_EXIT=1
trap - EXIT INT TERM HUP
if request_host_shutdown; then
  :
else
  shutdown_rc=$?
  FINAL_STATE=failed
  FINAL_REASON="shutdown-command-failed-$shutdown_rc"
  EXIT_CODE=72
  write_supervisor_status "$FINAL_STATE" "$FINAL_REASON"
  printf '%s: shutdown command failed with exit %s\n' "$PROGRAM" "$shutdown_rc" >&2
fi
exit "$EXIT_CODE"
