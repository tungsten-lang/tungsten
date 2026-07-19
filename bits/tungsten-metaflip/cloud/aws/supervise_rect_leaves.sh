#!/usr/bin/env bash
# NUMA-local, fail-closed supervisor for independent rectangular Metaflip leaves.
# The defaults map one selected rectangular profile to each NUMA node of an
# m8i.96xlarge.  The supervisor owns the wall deadline and, by default, shuts
# the AWS host down after every terminal campaign outcome so Spot spend stops.

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
RESTART_NONCE_BASE=1
DOOR_TICKET_BASE=0
POLL_SECONDS=2
DRAIN_SECONDS=120
STATUS_TIMEOUT=900
SHUTDOWN_ON_EXIT=1
SHUTDOWN_COMMAND=${METAFLIP_SHUTDOWN_COMMAND:-}
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: supervise_rect_leaves.sh --binary PATH [OPTIONS]

Launch one long-lived, CPU-only rectangular Metaflip leaf per NUMA node. The
default six-leaf campaign is the measured retarget for an m8i.96xlarge.

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
  -J, --walkers N            CPU walkers per leaf (default: 64)
  --steps N                  Moves per worker epoch (default: 500000)
  --restart-nonce-base N     First private rect restart nonce (default: 1)
  --door-ticket-base N       First private rect door ticket (default: 0)

Health and host policy:
  --poll-seconds N           Supervisor heartbeat interval (default: 2)
  --drain-seconds N          TERM grace before KILL (default: 120)
  --status-timeout N         Fail on a stale child heartbeat (default: 900)
  --shutdown                 Shut the host down after drain (default)
  --no-shutdown              Leave the host running after drain
  --shutdown-command PATH    Invoke PATH with no arguments instead of the
                             default `sudo shutdown -h now` (testing hook)

Other:
  --dry-run                  Validate and print commands; write nothing
  -h, --help                 Show this help

Every child is an explicit rectangular portfolio leaf. The supervisor refuses
square/unknown tensors, duplicate shapes or nodes, unequal shape/node counts,
and runtime/binary pairs missing the three private rectangular-leaf options.
An unexpected child exit, stale heartbeat, or observable kernel/cgroup OOM
drains all leaves. A clean exit is a successful record stop only when its final
status proves `best_rank <= target` or `wr_status=beats`. Supervisor status is
atomically replaced at:

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
    --restart-nonce-base)
      [ "$#" -ge 2 ] || die "--restart-nonce-base requires N"
      RESTART_NONCE_BASE=$2
      shift 2
      ;;
    --door-ticket-base)
      [ "$#" -ge 2 ] || die "--door-ticket-base requires N"
      DOOR_TICKET_BASE=$2
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
require_uint --restart-nonce-base "$RESTART_NONCE_BASE"
require_uint --door-ticket-base "$DOOR_TICKET_BASE"
require_uint --poll-seconds "$POLL_SECONDS"
require_uint --drain-seconds "$DRAIN_SECONDS"
require_uint --status-timeout "$STATUS_TIMEOUT"
[ "$WALKERS" -gt 0 ] || die "--walkers must be positive"
[ "$STEPS" -gt 0 ] || die "--steps must be positive"
[ "$RESTART_NONCE_BASE" -gt 0 ] || die "--restart-nonce-base must be positive"
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

# The allowlist mirrors lib/metaflip/seeds/rect.w. Admission means the package
# has a checked-in exact frontier and an explicit record target, not merely
# that the three dimensions can be parsed by the generic worker.
supported_rect_shape() {
  case "$1" in
    2x2x5|2x2x6|2x2x7|2x2x8|2x2x9|2x3x4|2x3x5|2x4x5|2x5x6|\
    3x3x4|3x3x5|3x4x4|3x4x5|3x4x6|3x4x7|3x5x5|3x5x6|3x5x7|\
    4x4x5|4x4x6|4x5x5|4x5x6|4x5x7|4x5x8|4x6x6|4x6x7|4x6x8|5x6x7)
      return 0
      ;;
  esac
  return 1
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
  supported_rect_shape "$shape" || \
    die "unsupported rectangular shape '$shape' (square and uncurated tensors are not leaves)"
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
# constructed command and reject the private leaf schedule only after spend
# begins. Require all three markers on both sides before launching anything.
command -v strings >/dev/null 2>&1 || die "strings is required to validate the native binary"
for rect_option in --rect-portfolio-child --rect-restart-nonce --rect-door-ticket; do
  grep -F -- "\"$rect_option\"" "$RUNTIME_ROOT/fleet.w" >/dev/null 2>&1 || \
    die "runtime does not advertise required rectangular option $rect_option"
  strings "$BINARY" 2>/dev/null | grep -F -- "$rect_option" >/dev/null || \
    die "native binary does not advertise required rectangular option $rect_option"
done

build_child_command() {
  local child_index=$1 shape node nonce ticket shape_state best_path status_path near_path tag
  shape=${SHAPES[$child_index]}
  node=${NODES[$child_index]}
  nonce=$((RESTART_NONCE_BASE + child_index))
  ticket=$((DOOR_TICKET_BASE + child_index))
  shape_state="$STATE_ROOT/$shape"
  best_path="$shape_state/best.txt"
  status_path="$shape_state/status.txt"
  near_path="$shape_state/near"
  tag="${CAMPAIGN_TAG}_${shape}_n${node}"

  CHILD_COMMAND=(
    setsid numactl "--cpunodebind=$node" "--membind=$node"
    "$BINARY"
    --tensor "$shape"
    --runtime-root "$RUNTIME_ROOT"
    --state-dir "$shape_state"
    --best "$best_path"
    --status "$status_path"
    --near-dir "$near_path"
    --run-tag "$tag"
    -J "$WALKERS"
    --steps "$STEPS"
    --secs 0
    --no-gpu
    --quiet
    --no-tui
    --stop-on-record
    --rect-portfolio-child
    --rect-restart-nonce "$nonce"
    --rect-door-ticket "$ticket"
  )

  BUILT_SHAPE=$shape
  BUILT_NODE=$node
  BUILT_NONCE=$nonce
  BUILT_TICKET=$ticket
  BUILT_STATE=$shape_state
  BUILT_BEST=$best_path
  BUILT_STATUS=$status_path
  BUILT_NEAR=$near_path
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
  printf 'DRY_RUN campaign=%s leaves=%d shapes=%s nodes=%s walkers=%d steps=%d seconds=%d shutdown=%d\n' \
    "$CAMPAIGN_TAG" "${#SHAPES[@]}" "$SHAPES_CSV" "$NODES_CSV" "$WALKERS" "$STEPS" "$DURATION" "$SHUTDOWN_ON_EXIT"
  index=0
  while [ "$index" -lt "${#SHAPES[@]}" ]; do
    build_child_command "$index"
    printf 'DRY_RUN leaf=%s node=%s nonce=%s ticket=%s state=%s best=%s status=%s near=%s log=%s\n' \
      "$BUILT_SHAPE" "$BUILT_NODE" "$BUILT_NONCE" "$BUILT_TICKET" "$BUILT_STATE" \
      "$BUILT_BEST" "$BUILT_STATUS" "$BUILT_NEAR" "$BUILT_LOG"
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
index=0
while [ "$index" -lt "${#SHAPES[@]}" ]; do
  mkdir -p "$STATE_ROOT/${SHAPES[$index]}" "$STATE_ROOT/${SHAPES[$index]}/near"
  index=$((index + 1))
done

exec 9>"$STATE_ROOT/supervisor/lock"
if ! flock -n 9; then
  die "another supervisor holds $STATE_ROOT/supervisor/lock"
fi

PIDS=()
CHILD_SHAPES=()
CHILD_NODES=()
CHILD_NONCES=()
CHILD_TICKETS=()
CHILD_BESTS=()
CHILD_STATUSES=()
CHILD_LOGS=()
CHILD_LAUNCH_EPOCHS=()
CHILD_REAPED=()
CHILD_EXIT_CODES=()
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
BEST_BY_SHAPE="none"

refresh_metrics() {
  local now=$1 i=0 line="" rank="" bits="" moves="" cpu_moves="" gpu_moves="" mtime="" age="" summary=""
  TOTAL_MOVES=0
  RUNNING_COUNT=0
  STATUS_COUNT=0
  STALE_COUNT=0
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ] && process_alive "${PIDS[$i]}"; then
      RUNNING_COUNT=$((RUNNING_COUNT + 1))
    fi
    rank=""
    bits=""
    moves=0
    if [ -s "${CHILD_STATUSES[$i]}" ]; then
      IFS= read -r line < "${CHILD_STATUSES[$i]}" || true
      STATUS_COUNT=$((STATUS_COUNT + 1))
      rank=$(field_from_line "$line" best_rank || true)
      bits=$(field_from_line "$line" best_bits || true)
      moves=$(field_from_line "$line" moves || true)
      case "$moves" in
        ''|*[!0-9]*)
          # Rectangular child status is schema=1 and reports its CPU/GPU
          # counters separately. Retain `moves` support for older/general
          # coordinators, but only fall back when that field is absent/bad.
          cpu_moves=$(field_from_line "$line" cpu_moves || true)
          gpu_moves=$(field_from_line "$line" gpu_moves || true)
          case "$cpu_moves" in ''|*[!0-9]*) cpu_moves=0 ;; esac
          case "$gpu_moves" in ''|*[!0-9]*) gpu_moves=0 ;; esac
          moves=$((cpu_moves + gpu_moves))
          ;;
      esac
      TOTAL_MOVES=$((TOTAL_MOVES + moves))
      mtime=$(file_mtime "${CHILD_STATUSES[$i]}" || true)
      case "$mtime" in ''|*[!0-9]*) mtime=$now ;; esac
      age=$((now - mtime))
      [ "$age" -le "$STATUS_TIMEOUT" ] || STALE_COUNT=$((STALE_COUNT + 1))
    elif [ $((now - START_EPOCH)) -gt "$STATUS_TIMEOUT" ]; then
      STALE_COUNT=$((STALE_COUNT + 1))
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
    "schema=1 producer_state=$producer_state updated_epoch=$now sequence=$STATUS_SEQUENCE campaign=$CAMPAIGN_TAG elapsed=$elapsed deadline_epoch=$DEADLINE_EPOCH shape_count=${#SHAPES[@]} launched_count=$LAUNCHED running_count=$RUNNING_COUNT status_count=$STATUS_COUNT stale_count=$STALE_COUNT total_moves=$TOTAL_MOVES shapes=$SHAPES_CSV nodes=$NODES_CSV best_by_shape=$BEST_BY_SHAPE oom_vm=$VM_OOM_NOW oom_cgroup=$CG_OOM_NOW oom_kill_cgroup=$CG_OOM_KILL_NOW reason=$reason" \
    > "$tmp"
  mv -f -- "$tmp" "$SUPERVISOR_STATUS"
}

write_pid_manifest() {
  local tmp="$PIDS_PATH.tmp.$$" i=0
  : > "$tmp"
  while [ "$i" -lt "$LAUNCHED" ]; do
    printf 'shape=%s pid=%s node=%s nonce=%s ticket=%s best=%s status=%s log=%s\n' \
      "${CHILD_SHAPES[$i]}" "${PIDS[$i]}" "${CHILD_NODES[$i]}" "${CHILD_NONCES[$i]}" \
      "${CHILD_TICKETS[$i]}" "${CHILD_BESTS[$i]}" "${CHILD_STATUSES[$i]}" "${CHILD_LOGS[$i]}" >> "$tmp"
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
  local child_index=$1 line tensor producer_state rank target wr_status mtime
  [ -s "${CHILD_STATUSES[$child_index]}" ] || return 1
  mtime=$(file_mtime "${CHILD_STATUSES[$child_index]}" || true)
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  [ "$mtime" -ge "${CHILD_LAUNCH_EPOCHS[$child_index]}" ] || return 1
  IFS= read -r line < "${CHILD_STATUSES[$child_index]}" || return 1
  tensor=$(field_from_line "$line" tensor || true)
  producer_state=$(field_from_line "$line" producer_state || true)
  rank=$(field_from_line "$line" best_rank || true)
  target=$(field_from_line "$line" target || true)
  wr_status=$(field_from_line "$line" wr_status || true)
  [ "$tensor" = "${CHILD_SHAPES[$child_index]}" ] || return 1
  [ "$producer_state" = stopped ] || return 1
  case "$rank" in ''|*[!0-9]*) return 1 ;; esac
  [ "$rank" -gt 0 ] || return 1
  if [ "$wr_status" = beats ]; then
    return 0
  fi
  case "$target" in ''|*[!0-9]*) return 1 ;; esac
  [ "$target" -gt 0 ] && [ "$rank" -le "$target" ]
}

unexpected_child_exit() {
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
        CHILD_EXIT_REASON="oom-child-${CHILD_SHAPES[$i]}-exit-$rc"
      else
        CHILD_EXIT_REASON="child-${CHILD_SHAPES[$i]}-exit-$rc"
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
    printf '%s: drain grace expired; KILLing %d remaining leaf/leaves\n' "$PROGRAM" "$RUNNING_COUNT" >&2
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

emergency_cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$CLEAN_EXIT" -eq 0 ] && [ "$LAUNCHED" -gt 0 ]; then
    printf '%s: emergency fail-closed drain of %d launched leaves\n' "$PROGRAM" "$LAUNCHED" >&2
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
      die "prior leaf PID $prior_pid is still live; inspect $PIDS_PATH before restarting"
    fi
  done < "$PIDS_PATH"
fi

index=0
while [ "$index" -lt "${#SHAPES[@]}" ]; do
  build_child_command "$index"
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
  CHILD_NONCES[$LAUNCHED]=$BUILT_NONCE
  CHILD_TICKETS[$LAUNCHED]=$BUILT_TICKET
  CHILD_BESTS[$LAUNCHED]=$BUILT_BEST
  CHILD_STATUSES[$LAUNCHED]=$BUILT_STATUS
  CHILD_LOGS[$LAUNCHED]=$BUILT_LOG
  CHILD_LAUNCH_EPOCHS[$LAUNCHED]=$child_launch_epoch
  CHILD_REAPED[$LAUNCHED]=0
  CHILD_EXIT_CODES[$LAUNCHED]=-1
  LAUNCHED=$((LAUNCHED + 1))
  write_pid_manifest
  printf '%s: launched %s pid=%s node=%s J=%s steps=%s nonce=%s ticket=%s\n' \
    "$PROGRAM" "$BUILT_SHAPE" "$pid" "$BUILT_NODE" "$WALKERS" "$STEPS" "$BUILT_NONCE" "$BUILT_TICKET" >&2

  if [ -n "$REQUESTED_REASON" ]; then
    drain_all "$REQUESTED_REASON"
    refresh_metrics "$(date +%s)"
    write_supervisor_status stopped "$REQUESTED_REASON"
    CLEAN_EXIT=1
    trap - EXIT INT TERM HUP
    signal_exit=0
    [ "$REQUESTED_REASON" != signal-int ] || signal_exit=130
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

[ "$LAUNCHED" -eq "${#SHAPES[@]}" ] || die "launched $LAUNCHED of ${#SHAPES[@]} leaves"

CHILD_EXIT_REASON=""
FINAL_REASON=""
printf '%s: campaign %s running %d leaves across nodes %s; status %s\n' \
  "$PROGRAM" "$CAMPAIGN_TAG" "$LAUNCHED" "$NODES_CSV" "$SUPERVISOR_STATUS" >&2

while :; do
  now=$(date +%s)
  refresh_metrics "$now"

  if detect_system_oom; then
    FINAL_REASON=oom-counter-increased
  elif unexpected_child_exit; then
    FINAL_REASON=$CHILD_EXIT_REASON
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
