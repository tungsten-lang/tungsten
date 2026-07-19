#!/usr/bin/env bash
# NUMA-local, fail-closed supervisor for a sharded square GF(2) Metaflip hunt.
# Target host: m8i.96xlarge (six NUMA nodes, 64 logical CPUs per node).

set -Eeuo pipefail
set -f
export LC_ALL=C

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROGRAM=${0##*/}
BINARY=${METAFLIP_BINARY:-}
RUNTIME_INPUT=${METAFLIP_RUNTIME_ROOT:-"$PACKAGE_ROOT/lib/metaflip"}
STATE_ROOT=${METAFLIP_STATE_ROOT:-}
STATE_ROOT_EXPLICIT=0
LOG_ROOT=${METAFLIP_LOG_ROOT:-}
LOG_ROOT_EXPLICIT=0
SEED_DIR=""
SEED_DIR_EXPLICIT=0

DURATION=7200
NODES_CSV="3,4,5"
SHARDS_PER_NODE=1
WALKERS=64
COMMON_STEPS=500000
NODE_STEPS_CSV="48000011,50000021,52000031"
NODE_STEPS_EXPLICIT=0
POLL_SECONDS=2
DRAIN_SECONDS=120
STATUS_TIMEOUT=900
SEED_NONCE_MODE=auto
DRY_RUN=0
CAMPAIGN_TAG=""

TENSOR=7x7
RECORD_RANK=247
TARGET_RANK=246

case "$STATE_ROOT" in '') ;; *) STATE_ROOT_EXPLICIT=1 ;; esac
case "$LOG_ROOT" in '') ;; *) LOG_ROOT_EXPLICIT=1 ;; esac

usage() {
  cat <<'EOF'
Usage: supervise_7x7.sh --binary PATH [OPTIONS]

Launch and supervise NUMA-local square CPU shards for GF(2) matrix
multiplication. The default remains the 7x7 campaign tuned for the upper half
(nodes 3,4,5) of a six-node m8i.96xlarge:

  1 shard per node, -J 64 per shard, 2 hours, CPU only
  node 3/4/5 step budgets 48000011/50000021/52000031

Required:
  --binary PATH              Native Metaflip coordinator executable

Campaign paths and duration:
  --tensor NxN               Square tensor, 2x2 through 7x7 (default: 7x7)
  --runtime-root PATH        Package, lib, or lib/metaflip root
  --state-root PATH          Parent for state/, best/, status/, near/, winner/
  --log-root PATH            Shard logs (default: STATE_ROOT/log)
  --seed-dir PATH            Curated exact record-rank seed directory
  --seconds N                Supervisor wall deadline; 0 means no deadline
  --campaign-tag TAG         Durable tag (default includes UTC timestamp + PID)

Topology and work:
  --nodes CSV                NUMA nodes (default: 3,4,5)
  --shards-per-node N        Default: 1
  -J, --walkers N            Walkers per shard (default: 64)
  --steps N                  Common steps once square --seed-nonce exists
  --node-steps CSV           Per-node steps while it does not (default above)
  --seed-nonce MODE          auto, on, or off (default: auto)

Health policy:
  --poll-seconds N           Supervisor heartbeat interval (default: 2)
  --drain-seconds N          Graceful TERM window before KILL (default: 120)
  --status-timeout N         Fail if a shard heartbeat is this stale (default: 900)

Other:
  --dry-run                  Validate and print every command; write nothing
  -h, --help                 Show this help

Every child exact-gates its explicit seed. Any malformed/inexact seed, early
child exit, stale heartbeat, or observable OOM drains the entire campaign.

Built-in GF(2) record ranks are 7, 23, 47, 93, 153, and 247 for 2x2 through
7x7 respectively. A winner is any exact scheme one rank below that baseline.
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
    --tensor)
      [ "$#" -ge 2 ] || die "--tensor requires NxN"
      TENSOR=$2
      shift 2
      ;;
    --state-root)
      [ "$#" -ge 2 ] || die "--state-root requires PATH"
      STATE_ROOT=$2
      STATE_ROOT_EXPLICIT=1
      shift 2
      ;;
    --log-root)
      [ "$#" -ge 2 ] || die "--log-root requires PATH"
      LOG_ROOT=$2
      LOG_ROOT_EXPLICIT=1
      shift 2
      ;;
    --seed-dir)
      [ "$#" -ge 2 ] || die "--seed-dir requires PATH"
      SEED_DIR=$2
      SEED_DIR_EXPLICIT=1
      shift 2
      ;;
    --seconds)
      [ "$#" -ge 2 ] || die "--seconds requires N"
      DURATION=$2
      shift 2
      ;;
    --nodes)
      [ "$#" -ge 2 ] || die "--nodes requires CSV"
      NODES_CSV=$2
      shift 2
      ;;
    --shards-per-node)
      [ "$#" -ge 2 ] || die "--shards-per-node requires N"
      SHARDS_PER_NODE=$2
      shift 2
      ;;
    -J|--walkers)
      [ "$#" -ge 2 ] || die "$1 requires N"
      WALKERS=$2
      shift 2
      ;;
    --steps)
      [ "$#" -ge 2 ] || die "--steps requires N"
      COMMON_STEPS=$2
      shift 2
      ;;
    --node-steps)
      [ "$#" -ge 2 ] || die "--node-steps requires CSV"
      NODE_STEPS_CSV=$2
      NODE_STEPS_EXPLICIT=1
      shift 2
      ;;
    --seed-nonce)
      [ "$#" -ge 2 ] || die "--seed-nonce requires auto, on, or off"
      SEED_NONCE_MODE=$2
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

case "$TENSOR" in
  2x2) RECORD_RANK=7 ;;
  3x3) RECORD_RANK=23 ;;
  4x4) RECORD_RANK=47 ;;
  5x5) RECORD_RANK=93 ;;
  6x6) RECORD_RANK=153 ;;
  7x7) RECORD_RANK=247 ;;
  *) die "--tensor must be square 2x2 through 7x7 (got '$TENSOR')" ;;
esac
TARGET_RANK=$((RECORD_RANK - 1))

if [ "$STATE_ROOT_EXPLICIT" -eq 0 ]; then
  STATE_ROOT="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/metaflip/${TENSOR}-sharded"
fi

require_uint --seconds "$DURATION"
require_uint --shards-per-node "$SHARDS_PER_NODE"
require_uint --walkers "$WALKERS"
require_uint --steps "$COMMON_STEPS"
require_uint --poll-seconds "$POLL_SECONDS"
require_uint --drain-seconds "$DRAIN_SECONDS"
require_uint --status-timeout "$STATUS_TIMEOUT"
[ "$SHARDS_PER_NODE" -gt 0 ] || die "--shards-per-node must be positive"
[ "$WALKERS" -gt 0 ] || die "--walkers must be positive"
[ "$COMMON_STEPS" -gt 0 ] || die "--steps must be positive"
[ "$POLL_SECONDS" -gt 0 ] || die "--poll-seconds must be positive"
[ "$DRAIN_SECONDS" -gt 0 ] || die "--drain-seconds must be positive"
[ "$STATUS_TIMEOUT" -gt 0 ] || die "--status-timeout must be positive"

case "$SEED_NONCE_MODE" in
  auto|on|off) ;;
  *) die "--seed-nonce must be auto, on, or off" ;;
esac

case "$CAMPAIGN_TAG" in
  *[!A-Za-z0-9_.-]*) die "--campaign-tag may contain only letters, digits, '.', '_', and '-'" ;;
esac
if [ -z "$CAMPAIGN_TAG" ]; then
  CAMPAIGN_TAG="aws_${TENSOR}_sharded_$(date -u +%Y%m%dT%H%M%SZ)_$$"
fi

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
if [ "$SEED_DIR_EXPLICIT" -eq 0 ]; then
  SEED_DIR="$RUNTIME_ROOT/seeds/gf2"
fi
[ -d "$SEED_DIR" ] || die "seed directory does not exist: $SEED_DIR"

if [ "$LOG_ROOT_EXPLICIT" -eq 0 ]; then
  LOG_ROOT="$STATE_ROOT/log"
fi

OLD_IFS=$IFS
IFS=,
NODES=( $NODES_CSV )
IFS=$OLD_IFS
[ "${#NODES[@]}" -gt 0 ] || die "--nodes is empty"

node_index=0
while [ "$node_index" -lt "${#NODES[@]}" ]; do
  node=${NODES[$node_index]}
  require_uint --nodes "$node"
  prior=0
  while [ "$prior" -lt "$node_index" ]; do
    [ "${NODES[$prior]}" != "$node" ] || die "duplicate NUMA node $node"
    prior=$((prior + 1))
  done
  node_index=$((node_index + 1))
done

seed_nonce_available=0
case "$SEED_NONCE_MODE" in
  on)
    seed_nonce_available=1
    ;;
  off)
    seed_nonce_available=0
    ;;
  auto)
    # Require both the runtime parser and the native executable to advertise
    # the option. This avoids handing a newly-synced runtime flag to an older,
    # still-warm binary. Plain grep (not -q) lets strings finish under pipefail.
    if grep -Fq '"--seed-nonce"' "$RUNTIME_ROOT/fleet.w" 2>/dev/null \
       && command -v strings >/dev/null 2>&1 \
       && strings "$BINARY" 2>/dev/null | grep -F -- '--seed-nonce' >/dev/null; then
      seed_nonce_available=1
    fi
    ;;
esac

NODE_STEPS=()
if [ "$seed_nonce_available" -eq 0 ]; then
  if [ "$NODE_STEPS_EXPLICIT" -eq 1 ]; then
    IFS=,
    NODE_STEPS=( $NODE_STEPS_CSV )
    IFS=$OLD_IFS
    [ "${#NODE_STEPS[@]}" -eq "${#NODES[@]}" ] || \
      die "--node-steps needs one value per NUMA node"
  elif [ "${#NODES[@]}" -eq 3 ] && [ "$NODES_CSV" = "3,4,5" ] && [ "$COMMON_STEPS" -eq 500000 ]; then
    # Older binaries lack the adaptive wide-fleet cadence as well as the
    # square nonce.  The measured one-node knee is near 50M steps, so keep
    # those binaries productive while odd, node-specific values desynchronize
    # otherwise repeated streams.
    NODE_STEPS=(48000011 50000021 52000031)
  else
    # Keep custom topologies desynchronized without making the center budget
    # materially different from --steps. Odd jitters avoid common divisors.
    node_index=0
    node_count=${#NODES[@]}
    while [ "$node_index" -lt "$node_count" ]; do
      offset=$(( (2 * node_index - (node_count - 1)) * 10000 ))
      value=$(( COMMON_STEPS + offset + 11 + 10 * node_index ))
      [ "$value" -gt 0 ] || die "derived node step budget is not positive; pass --node-steps"
      NODE_STEPS[$node_index]=$value
      node_index=$((node_index + 1))
    done
  fi
  node_index=0
  while [ "$node_index" -lt "${#NODE_STEPS[@]}" ]; do
    require_uint --node-steps "${NODE_STEPS[$node_index]}"
    [ "${NODE_STEPS[$node_index]}" -gt 0 ] || die "node step budgets must be positive"
    prior=0
    while [ "$prior" -lt "$node_index" ]; do
      [ "${NODE_STEPS[$prior]}" != "${NODE_STEPS[$node_index]}" ] || \
        die "per-node step budgets must differ until square --seed-nonce exists"
      prior=$((prior + 1))
    done
    node_index=$((node_index + 1))
  done
fi

scheme_declared_rank() {
  local path=$1 first fields
  first=$(sed -n '1p' "$path" 2>/dev/null || true)
  fields=$(printf '%s\n' "$first" | awk '{ print NF }')
  if [ "$fields" -eq 1 ]; then
    case "$first" in
      ''|*[!0-9]*) ;;
      *) printf '%s\n' "$first"; return 0 ;;
    esac
  fi
  awk 'NF { count += 1 } END { print count + 0 }' "$path"
}

SEEDS=()
# Globbing is disabled globally so status tokens and CSV values cannot expand
# against the working directory. Enable it only for this quoted seed prefix.
set +f
for candidate in "$SEED_DIR"/matmul_"$TENSOR"_rank"$RECORD_RANK"*_gf2.txt; do
  [ -f "$candidate" ] || continue
  rank=$(scheme_declared_rank "$candidate")
  [ "$rank" -eq "$RECORD_RANK" ] || \
    die "$TENSOR rank-$RECORD_RANK seed has structural rank $rank: $candidate"
  SEEDS[${#SEEDS[@]}]=$candidate
done
set -f
[ "${#SEEDS[@]}" -gt 0 ] || \
  die "no matmul_${TENSOR}_rank${RECORD_RANK}*_gf2.txt seeds in $SEED_DIR"
TOTAL_CHILDREN=$(( ${#NODES[@]} * SHARDS_PER_NODE ))
# A small square may have fewer curated record representatives than NUMA
# nodes. Unique shard nonces (or the legacy per-node step jitter) still give
# repeated anchors independent streams. Without nonce support, multiple
# shards on one node need distinct seeds because their node cadence is shared.
required_seeds=1
if [ "$TENSOR" = 7x7 ]; then
  # Preserve the original 7x7 launcher's stronger anchor-diversity gate.
  required_seeds=$SHARDS_PER_NODE
  if [ "${#NODES[@]}" -gt "$required_seeds" ]; then
    required_seeds=${#NODES[@]}
  fi
elif [ "$seed_nonce_available" -eq 0 ] && [ "$SHARDS_PER_NODE" -gt 1 ]; then
  required_seeds=$SHARDS_PER_NODE
fi
[ "${#SEEDS[@]}" -ge "$required_seeds" ] || \
  die "need at least $required_seeds $TENSOR rank-$RECORD_RANK seeds for this topology (found ${#SEEDS[@]})"

shard_id_for() {
  printf 'n%s-s%02d' "$1" "$2"
}

build_child_command() {
  local node_idx=$1 local_shard=$2 global_shard=$3
  local node=${NODES[$node_idx]}
  local id seed steps state_path best_path status_path near_path tag
  id=$(shard_id_for "$node" "$local_shard")
  seed=${SEEDS[$((global_shard % ${#SEEDS[@]}))]}
  if [ "$seed_nonce_available" -eq 1 ]; then
    steps=$COMMON_STEPS
  else
    steps=${NODE_STEPS[$node_idx]}
  fi
  state_path="$STATE_ROOT/state/$id"
  best_path="$STATE_ROOT/best/$id.txt"
  status_path="$STATE_ROOT/status/$id.txt"
  near_path="$STATE_ROOT/near/$id"
  tag="${CAMPAIGN_TAG}_${id}"

  CHILD_COMMAND=(
    setsid numactl "--cpunodebind=$node" "--membind=$node"
    "$BINARY"
    --tensor "$TENSOR"
    --runtime-root "$RUNTIME_ROOT"
    --seed "$seed"
    -J "$WALKERS"
    --steps "$steps"
    --secs 0
    --no-gpu
    --no-tui
    --stop-on-record
    --state-dir "$state_path"
    --best "$best_path"
    --status "$status_path"
    --near-dir "$near_path"
    --run-tag "$tag"
  )
  if [ "$seed_nonce_available" -eq 1 ]; then
    CHILD_COMMAND+=(--seed-nonce "$((global_shard + 1))")
  fi

  BUILT_ID=$id
  BUILT_NODE=$node
  BUILT_SEED=$seed
  BUILT_STEPS=$steps
  BUILT_STATE=$state_path
  BUILT_BEST=$best_path
  BUILT_STATUS=$status_path
  BUILT_NEAR=$near_path
  BUILT_LOG="$LOG_ROOT/$id.log"
}

print_command() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$seed_nonce_available" -eq 1 ]; then
    diversity=seed-nonce
  else
    diversity=per-node-steps
  fi
  printf 'DRY_RUN campaign=%s tensor=%s record_rank=%d target_rank=%d children=%d nodes=%s shards_per_node=%d walkers=%d seconds=%d diversity=%s seeds=%d\n' \
    "$CAMPAIGN_TAG" "$TENSOR" "$RECORD_RANK" "$TARGET_RANK" "$TOTAL_CHILDREN" "$NODES_CSV" "$SHARDS_PER_NODE" "$WALKERS" "$DURATION" "$diversity" "${#SEEDS[@]}"
  global_shard=0
  node_index=0
  while [ "$node_index" -lt "${#NODES[@]}" ]; do
    local_shard=0
    while [ "$local_shard" -lt "$SHARDS_PER_NODE" ]; do
      build_child_command "$node_index" "$local_shard" "$global_shard"
      printf 'DRY_RUN shard=%s node=%s local=%d global=%d steps=%s seed=%s state=%s best=%s status=%s near=%s log=%s\n' \
        "$BUILT_ID" "$BUILT_NODE" "$local_shard" "$global_shard" "$BUILT_STEPS" "$BUILT_SEED" \
        "$BUILT_STATE" "$BUILT_BEST" "$BUILT_STATUS" "$BUILT_NEAR" "$BUILT_LOG"
      print_command "${CHILD_COMMAND[@]}"
      global_shard=$((global_shard + 1))
      local_shard=$((local_shard + 1))
    done
    node_index=$((node_index + 1))
  done
  exit 0
fi

command -v numactl >/dev/null 2>&1 || die "numactl is required"
command -v setsid >/dev/null 2>&1 || die "setsid is required"
command -v flock >/dev/null 2>&1 || die "flock is required"

node_index=0
while [ "$node_index" -lt "${#NODES[@]}" ]; do
  node=${NODES[$node_index]}
  [ -d "/sys/devices/system/node/node$node" ] || die "NUMA node $node is not present on this host"
  node_index=$((node_index + 1))
done

mkdir -p \
  "$STATE_ROOT/state" "$STATE_ROOT/best" "$STATE_ROOT/status" \
  "$STATE_ROOT/near" "$STATE_ROOT/supervisor" "$STATE_ROOT/winner" \
  "$LOG_ROOT"

exec 9>"$STATE_ROOT/supervisor/lock"
if ! flock -n 9; then
  die "another supervisor holds $STATE_ROOT/supervisor/lock"
fi

# The lock descriptor is deliberately closed in each child. If the supervisor
# itself is SIGKILLed, refuse a duplicate launch while a manifest PID still has
# this campaign's state root in its command line.
prior_manifest="$STATE_ROOT/supervisor/pids.txt"
if [ -s "$prior_manifest" ]; then
  while IFS= read -r prior_line; do
    prior_pid=""
    for prior_token in $prior_line; do
      case "$prior_token" in pid=*) prior_pid=${prior_token#pid=} ;; esac
    done
    case "$prior_pid" in ''|*[!0-9]*) continue ;; esac
    if kill -0 "$prior_pid" 2>/dev/null && [ -r "/proc/$prior_pid/cmdline" ] \
       && tr '\000' ' ' < "/proc/$prior_pid/cmdline" | grep -F -- "$STATE_ROOT/state/" >/dev/null; then
      die "prior shard PID $prior_pid is still live; inspect $prior_manifest before restarting"
    fi
  done < "$prior_manifest"
fi

PIDS=()
CHILD_IDS=()
CHILD_NODES=()
CHILD_SEEDS=()
CHILD_STEPS=()
CHILD_BESTS=()
CHILD_STATUSES=()
CHILD_LOGS=()
CHILD_REAPED=()
CHILD_EXIT_CODES=()
LAUNCHED=0
CLEAN_EXIT=0
REQUESTED_REASON=""
PHASE=starting
SUPERVISOR_STATUS="$STATE_ROOT/supervisor/status.txt"
PIDS_PATH="$STATE_ROOT/supervisor/pids.txt"
STATUS_SEQUENCE=0
WINNER_INDEX=-1
WINNER_RANK=999999
WINNER_PRESERVED=0
PRESERVED_RANK=999999
WINNER_ARTIFACT=""
START_EPOCH=$(date +%s)
if [ "$DURATION" -gt 0 ]; then
  DEADLINE_EPOCH=$((START_EPOCH + DURATION))
else
  DEADLINE_EPOCH=0
fi

process_alive() {
  local pid=$1 stat_line rest state
  kill -0 "$pid" 2>/dev/null || return 1
  # kill -0 also succeeds for an unreaped zombie. On Linux, exclude it so a
  # cleanly stopped child does not consume the entire drain grace period.
  if [ -r "/proc/$pid/stat" ]; then
    IFS= read -r stat_line < "/proc/$pid/stat" || return 1
    rest=${stat_line##*) }
    state=${rest%% *}
    [ "$state" != Z ] || return 1
  fi
  return 0
}

terminate_groups() {
  local signal=$1 i=0 pid
  while [ "$i" -lt "$LAUNCHED" ]; do
    pid=${PIDS[$i]}
    if [ "${CHILD_REAPED[$i]}" -eq 0 ]; then
      kill -"$signal" -- "-$pid" 2>/dev/null || true
    fi
    i=$((i + 1))
  done
}

emergency_cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  if [ "$CLEAN_EXIT" -eq 0 ] && [ "$LAUNCHED" -gt 0 ]; then
    printf '%s: emergency fail-closed drain of %d launched shards\n' "$PROGRAM" "$LAUNCHED" >&2
    terminate_groups TERM
    sleep 2
    terminate_groups KILL
    i=0
    while [ "$i" -lt "$LAUNCHED" ]; do
      wait "${PIDS[$i]}" 2>/dev/null
      i=$((i + 1))
    done
  fi
  exit "$rc"
}

trap emergency_cleanup EXIT
trap 'REQUESTED_REASON=signal-int' INT
trap 'REQUESTED_REASON=signal-term' TERM
trap 'REQUESTED_REASON=signal-hup' HUP

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
  case "$first" in
    ''|*[!0-9]*) return 1 ;;
    *) printf '%s\n' "$first" ;;
  esac
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
CGROUP_EVENTS_PATH=""
if [ -r /proc/self/cgroup ] && [ -d /sys/fs/cgroup ]; then
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
AGG_BEST=999999
AGG_BEST_BITS=999999999
AGG_BEST_COUNT=0
STATUS_COUNT=0
RUNNING_COUNT=0
STALE_COUNT=0

refresh_metrics() {
  local now=$1 i=0 line="" rank="" bits="" moves="" best_rank="" mtime="" age=""
  local file_best=999999 file_best_count=0
  TOTAL_MOVES=0
  AGG_BEST=999999
  AGG_BEST_BITS=999999999
  AGG_BEST_COUNT=0
  STATUS_COUNT=0
  RUNNING_COUNT=0
  STALE_COUNT=0
  WINNER_INDEX=-1
  WINNER_RANK=999999
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ] && process_alive "${PIDS[$i]}"; then
      RUNNING_COUNT=$((RUNNING_COUNT + 1))
    fi
    line=""
    rank=""
    bits=""
    moves=""
    best_rank=""
    if [ -s "${CHILD_STATUSES[$i]}" ]; then
      IFS= read -r line < "${CHILD_STATUSES[$i]}" || true
      STATUS_COUNT=$((STATUS_COUNT + 1))
      rank=$(field_from_line "$line" best_rank || true)
      bits=$(field_from_line "$line" best_bits || true)
      moves=$(field_from_line "$line" moves || true)
      case "$moves" in ''|*[!0-9]*) moves=0 ;; esac
      TOTAL_MOVES=$((TOTAL_MOVES + moves))
      case "$rank" in ''|*[!0-9]*) rank="" ;; esac
      case "$bits" in ''|*[!0-9]*) bits=999999999 ;; esac
      if [ -n "$rank" ]; then
        if [ "$rank" -lt "$AGG_BEST" ]; then
          AGG_BEST=$rank
          AGG_BEST_BITS=$bits
          AGG_BEST_COUNT=1
        elif [ "$rank" -eq "$AGG_BEST" ]; then
          AGG_BEST_COUNT=$((AGG_BEST_COUNT + 1))
          [ "$bits" -ge "$AGG_BEST_BITS" ] || AGG_BEST_BITS=$bits
        fi
        if [ "$rank" -le "$TARGET_RANK" ] && [ "$rank" -lt "$WINNER_RANK" ]; then
          WINNER_INDEX=$i
          WINNER_RANK=$rank
        fi
      fi
      mtime=$(file_mtime "${CHILD_STATUSES[$i]}" || true)
      case "$mtime" in ''|*[!0-9]*) mtime=$now ;; esac
      age=$((now - mtime))
      [ "$age" -le "$STATUS_TIMEOUT" ] || STALE_COUNT=$((STALE_COUNT + 1))
    elif [ $((now - START_EPOCH)) -gt "$STATUS_TIMEOUT" ]; then
      STALE_COUNT=$((STALE_COUNT + 1))
    fi

    best_rank=$(first_rank "${CHILD_BESTS[$i]}" || true)
    case "$best_rank" in ''|*[!0-9]*) best_rank="" ;; esac
    if [ -n "$best_rank" ]; then
      if [ "$best_rank" -lt "$file_best" ]; then
        file_best=$best_rank
        file_best_count=1
      elif [ "$best_rank" -eq "$file_best" ]; then
        file_best_count=$((file_best_count + 1))
      fi
    fi
    if [ -n "$best_rank" ] && [ "$best_rank" -le "$TARGET_RANK" ] && [ "$best_rank" -lt "$WINNER_RANK" ]; then
      WINNER_INDEX=$i
      WINNER_RANK=$best_rank
    fi
    i=$((i + 1))
  done
  if [ "$AGG_BEST" -eq 999999 ]; then
    AGG_BEST=$file_best
    AGG_BEST_BITS=0
    AGG_BEST_COUNT=$file_best_count
    if [ "$AGG_BEST" -eq 999999 ]; then
      AGG_BEST=0
      AGG_BEST_COUNT=0
    fi
  fi
}

write_supervisor_status() {
  local producer_state=$1 reason=$2 now elapsed deadline tmp
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  if [ "$DURATION" -gt 0 ]; then deadline=$DEADLINE_EPOCH; else deadline=0; fi
  STATUS_SEQUENCE=$((STATUS_SEQUENCE + 1))
  tmp="$SUPERVISOR_STATUS.tmp.$$.$STATUS_SEQUENCE"
  printf '%s\n' \
    "schema=1 producer_state=$producer_state updated_epoch=$now sequence=$STATUS_SEQUENCE campaign=$CAMPAIGN_TAG tensor=$TENSOR record_rank=$RECORD_RANK target_rank=$TARGET_RANK elapsed=$elapsed deadline_epoch=$deadline child_count=$LAUNCHED expected_count=$TOTAL_CHILDREN running_count=$RUNNING_COUNT status_count=$STATUS_COUNT stale_count=$STALE_COUNT total_moves=$TOTAL_MOVES best_rank=$AGG_BEST best_bits=$AGG_BEST_BITS best_count=$AGG_BEST_COUNT winner_count=$WINNER_PRESERVED oom_vm=$VM_OOM_NOW oom_cgroup=$CG_OOM_NOW oom_kill_cgroup=$CG_OOM_KILL_NOW reason=$reason" \
    > "$tmp"
  mv -f -- "$tmp" "$SUPERVISOR_STATUS"
}

write_pid_manifest() {
  local tmp="$PIDS_PATH.tmp.$$" i=0
  : > "$tmp"
  while [ "$i" -lt "$LAUNCHED" ]; do
    printf 'shard=%s pid=%s node=%s steps=%s seed=%s best=%s status=%s log=%s\n' \
      "${CHILD_IDS[$i]}" "${PIDS[$i]}" "${CHILD_NODES[$i]}" "${CHILD_STEPS[$i]}" \
      "${CHILD_SEEDS[$i]}" "${CHILD_BESTS[$i]}" "${CHILD_STATUSES[$i]}" "${CHILD_LOGS[$i]}" >> "$tmp"
    i=$((i + 1))
  done
  mv -f -- "$tmp" "$PIDS_PATH"
}

preserve_winner() {
  local index=$1 source rank id stamp artifact tmp meta_tmp current_tmp copied_rank
  [ "$index" -ge 0 ] || return 1
  source=${CHILD_BESTS[$index]}
  rank=$(first_rank "$source" || true)
  case "$rank" in ''|*[!0-9]*) return 1 ;; esac
  [ "$rank" -le "$TARGET_RANK" ] || return 1
  id=${CHILD_IDS[$index]}
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  artifact="$STATE_ROOT/winner/${CAMPAIGN_TAG}_${id}_r${rank}_${stamp}.txt"
  tmp="$artifact.tmp.$$"
  cp -- "$source" "$tmp"
  copied_rank=$(first_rank "$tmp" || true)
  [ "$copied_rank" = "$rank" ] || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$artifact"

  current_tmp="$STATE_ROOT/winner/current.txt.tmp.$$"
  cp -- "$artifact" "$current_tmp"
  mv -f -- "$current_tmp" "$STATE_ROOT/winner/current.txt"
  meta_tmp="$STATE_ROOT/winner/current.meta.tmp.$$"
  printf 'campaign=%s shard=%s node=%s rank=%s seed=%s source_best=%s source_status=%s source_log=%s artifact=%s preserved_epoch=%s\n' \
    "$CAMPAIGN_TAG" "$id" "${CHILD_NODES[$index]}" "$rank" "${CHILD_SEEDS[$index]}" \
    "$source" "${CHILD_STATUSES[$index]}" "${CHILD_LOGS[$index]}" "$artifact" "$(date +%s)" > "$meta_tmp"
  mv -f -- "$meta_tmp" "$STATE_ROOT/winner/current.meta"
  WINNER_PRESERVED=1
  PRESERVED_RANK=$rank
  WINNER_ARTIFACT=$artifact
  WINNER_RANK=$rank
  printf '%s: preserved rank-%s winner from %s at %s\n' "$PROGRAM" "$rank" "$id" "$artifact" >&2
  return 0
}

reap_child() {
  local index=$1 rc
  if [ "${CHILD_REAPED[$index]}" -eq 1 ]; then
    REAP_RC=${CHILD_EXIT_CODES[$index]}
    return 0
  fi
  if wait "${PIDS[$index]}"; then rc=0; else rc=$?; fi
  CHILD_REAPED[$index]=1
  CHILD_EXIT_CODES[$index]=$rc
  REAP_RC=$rc
}

unexpected_child_exit() {
  local i=0 rc log
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ] && ! process_alive "${PIDS[$i]}"; then
      reap_child "$i"
      rc=$REAP_RC
      log=${CHILD_LOGS[$i]}
      if [ "$rc" -eq 137 ] || [ "$rc" -eq 9 ] \
         || grep -Eiq 'out of memory|oom-kill|oom killer|cannot allocate memory|std::bad_alloc|Killed process' "$log" 2>/dev/null; then
        FAILURE_REASON="oom-child-${CHILD_IDS[$i]}-exit-$rc"
      else
        FAILURE_REASON="child-${CHILD_IDS[$i]}-exit-$rc"
      fi
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

drain_all() {
  local reason=$1 drain_deadline now i rc
  PHASE=draining
  refresh_metrics "$(date +%s)"
  write_supervisor_status draining "$reason"
  terminate_groups TERM
  drain_deadline=$(( $(date +%s) + DRAIN_SECONDS ))
  while :; do
    now=$(date +%s)
    refresh_metrics "$now"
    if [ "$WINNER_INDEX" -ge 0 ] && { [ "$WINNER_PRESERVED" -eq 0 ] || [ "$WINNER_RANK" -lt "$PRESERVED_RANK" ]; }; then
      preserve_winner "$WINNER_INDEX" || true
    fi
    write_supervisor_status draining "$reason"
    [ "$RUNNING_COUNT" -gt 0 ] || break
    [ "$now" -lt "$drain_deadline" ] || break
    # A trapped INT/TERM interrupts sleep with a nonzero status; keep control
    # in the main loop so the requested graceful drain still runs under -e.
    sleep "$POLL_SECONDS" || true
  done
  if [ "$RUNNING_COUNT" -gt 0 ]; then
    printf '%s: drain grace expired; KILLing %d remaining shard(s)\n' "$PROGRAM" "$RUNNING_COUNT" >&2
    terminate_groups KILL
  fi
  i=0
  while [ "$i" -lt "$LAUNCHED" ]; do
    if [ "${CHILD_REAPED[$i]}" -eq 0 ]; then
      reap_child "$i"
      rc=$REAP_RC
      : "$rc"
    fi
    i=$((i + 1))
  done
  refresh_metrics "$(date +%s)"
  if [ "$WINNER_INDEX" -ge 0 ] && { [ "$WINNER_PRESERVED" -eq 0 ] || [ "$WINNER_RANK" -lt "$PRESERVED_RANK" ]; }; then
    preserve_winner "$WINNER_INDEX" || true
  fi
}

# Do not trust a stale heartbeat from an earlier invocation. Keep it for
# forensics, while durable best/near/state paths intentionally resume.
global_shard=0
node_index=0
while [ "$node_index" -lt "${#NODES[@]}" ]; do
  local_shard=0
  while [ "$local_shard" -lt "$SHARDS_PER_NODE" ]; do
    build_child_command "$node_index" "$local_shard" "$global_shard"
    mkdir -p "$BUILT_STATE" "$BUILT_NEAR"
    if [ -e "$BUILT_STATUS" ]; then
      mv -f -- "$BUILT_STATUS" "$BUILT_STATUS.previous.$CAMPAIGN_TAG"
    fi
    if [ -e "$BUILT_LOG" ]; then
      mv -f -- "$BUILT_LOG" "$BUILT_LOG.previous.$CAMPAIGN_TAG"
    fi
    : > "$BUILT_LOG"

    # Close the supervisor's flock descriptor in children. A stale manifest
    # then remains inspectable after a supervisor SIGKILL instead of an orphan
    # silently retaining the lock forever.
    "${CHILD_COMMAND[@]}" 9>&- >> "$BUILT_LOG" 2>&1 &
    pid=$!
    PIDS[$LAUNCHED]=$pid
    CHILD_IDS[$LAUNCHED]=$BUILT_ID
    CHILD_NODES[$LAUNCHED]=$BUILT_NODE
    CHILD_SEEDS[$LAUNCHED]=$BUILT_SEED
    CHILD_STEPS[$LAUNCHED]=$BUILT_STEPS
    CHILD_BESTS[$LAUNCHED]=$BUILT_BEST
    CHILD_STATUSES[$LAUNCHED]=$BUILT_STATUS
    CHILD_LOGS[$LAUNCHED]=$BUILT_LOG
    CHILD_REAPED[$LAUNCHED]=0
    CHILD_EXIT_CODES[$LAUNCHED]=-1
    LAUNCHED=$((LAUNCHED + 1))
    write_pid_manifest
    printf '%s: launched %s pid=%s node=%s J=%s steps=%s seed=%s\n' \
      "$PROGRAM" "$BUILT_ID" "$pid" "$BUILT_NODE" "$WALKERS" "$BUILT_STEPS" "${BUILT_SEED##*/}" >&2

    if [ -n "$REQUESTED_REASON" ]; then
      drain_all "$REQUESTED_REASON"
      CLEAN_EXIT=1
      trap - EXIT INT TERM HUP
      exit 130
    fi
    global_shard=$((global_shard + 1))
    local_shard=$((local_shard + 1))
  done
  node_index=$((node_index + 1))
done

[ "$LAUNCHED" -eq "$TOTAL_CHILDREN" ] || die "launched $LAUNCHED of $TOTAL_CHILDREN shards"

PHASE=running
FAILURE_REASON=""
FINAL_REASON=""

printf '%s: campaign %s running %d shards across nodes %s; status %s\n' \
  "$PROGRAM" "$CAMPAIGN_TAG" "$LAUNCHED" "$NODES_CSV" "$SUPERVISOR_STATUS" >&2

while :; do
  now=$(date +%s)
  refresh_metrics "$now"

  if [ "$WINNER_INDEX" -ge 0 ]; then
    preserve_winner "$WINNER_INDEX" || true
    FINAL_REASON="winner-rank-$WINNER_RANK-${CHILD_IDS[$WINNER_INDEX]}"
  elif detect_system_oom; then
    FINAL_REASON="oom-counter-increased"
  elif unexpected_child_exit; then
    FINAL_REASON=$FAILURE_REASON
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
  winner-*)
    if [ "$WINNER_PRESERVED" -eq 1 ]; then
      FINAL_STATE=winner
      EXIT_CODE=0
    else
      FINAL_REASON="winner-artifact-missing"
      EXIT_CODE=72
    fi
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
printf '%s: campaign %s state=%s reason=%s total_moves=%s best_rank=%s winner=%s\n' \
  "$PROGRAM" "$CAMPAIGN_TAG" "$FINAL_STATE" "$FINAL_REASON" "$TOTAL_MOVES" "$AGG_BEST" "${WINNER_ARTIFACT:-none}" >&2

CLEAN_EXIT=1
trap - EXIT INT TERM HUP
exit "$EXIT_CODE"
