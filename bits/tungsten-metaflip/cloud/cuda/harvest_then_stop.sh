#!/bin/sh
# Poll a Runpod campaign, take a source-hashed stable snapshot, and stop the
# pod only after the complete local copy verifies.  This script deliberately
# has no delete/terminate path: a failure leaves the pod and its disk alone.
set -u

PROGRAM=${0##*/}

POD_ID=
SSH_HOST=
SSH_PORT=22
SSH_USER=root
SSH_KEY=
REMOTE_WORKSPACE=/workspace
LOCAL_DESTINATION=
STATUS_FILE=results/status.txt
PROCESS_PATTERN=metaflip-cuda-777
POLL_SECONDS=30
SNAPSHOT_ATTEMPTS=3
SNAPSHOT_DELAY=2
ONCE=0
DRY_RUN=0
RESULT_PATHS=

SSH_CMD=${METAFLIP_HARVEST_SSH:-ssh}
RSYNC_CMD=${METAFLIP_HARVEST_RSYNC:-rsync}
RUNPODCTL_CMD=${METAFLIP_HARVEST_RUNPODCTL:-runpodctl}
SLEEP_CMD=${METAFLIP_HARVEST_SLEEP:-sleep}

usage() {
  cat <<'EOF'
usage: harvest_then_stop.sh OPTIONS

Required:
  --pod-id ID                 Runpod pod id
  --ssh-host HOST             Runpod SSH host
  --local-destination PATH    new local directory for the verified snapshot

Connection and paths:
  --ssh-port N                SSH port (default: 22)
  --ssh-user USER             SSH user (default: root)
  --ssh-key PATH              private key (optional)
  --remote-workspace PATH     remote campaign root (default: /workspace)
  --status-file RELPATH       status relative to workspace
                              (default: results/status.txt)
  --result-path RELPATH       result file/directory to preserve; repeatable
                              (default when omitted: results)
  --process-pattern TEXT      pgrep -f substring for the campaign process
                              (default: metaflip-cuda-777)

Polling and safety:
  --poll-seconds N            delay between nonterminal polls (default: 30)
  --snapshot-attempts N       retries for a changing source (default: 3)
  --snapshot-delay N          seconds before the post-copy hash (default: 2)
  --once                      poll once; exit 3 if the campaign is active
  --dry-run                   validate and print the plan; run no commands
  -h, --help                  show this help

For the mixed CUDA/CPU campaign, preserve both result trees with:
  --result-path results --result-path cpu-results-445

Testing overrides (each value must name one executable):
  METAFLIP_HARVEST_SSH, METAFLIP_HARVEST_RSYNC,
  METAFLIP_HARVEST_RUNPODCTL, METAFLIP_HARVEST_SLEEP
EOF
}

die() {
  echo "$PROGRAM: $*" >&2
  exit 1
}

need_value() {
  option=$1
  count=$2
  if [ "$count" -lt 2 ]; then
    echo "$PROGRAM: $option requires a value" >&2
    usage >&2
    exit 2
  fi
}

require_uint() {
  label=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) die "$label must be a nonnegative integer" ;;
  esac
}

require_positive_uint() {
  label=$1
  value=$2
  require_uint "$label" "$value"
  [ "$value" -gt 0 ] || die "$label must be greater than zero"
}

# Remote paths are intentionally narrower than local paths.  They are embedded
# in rsync's remote-source syntax, so accepting shell metacharacters here would
# make a preservation helper an injection surface.
require_safe_remote_path() {
  label=$1
  value=$2
  case "$value" in
    ''|*[!A-Za-z0-9._/-]*) die "$label contains an unsupported character: $value" ;;
  esac
  case "/$value/" in
    */../*|*/./*) die "$label may not contain . or .. path components: $value" ;;
  esac
}

require_relative_result_path() {
  value=$1
  require_safe_remote_path "--result-path" "$value"
  case "$value" in
    /*|.|..|*/|*//*) die "--result-path must be a normalized relative path: $value" ;;
    .metaflip-harvest|.metaflip-harvest/*)
      die "--result-path uses the guard's reserved manifest directory: $value" ;;
  esac
}

append_result_path() {
  new_path=$1
  require_relative_result_path "$new_path"

  old_ifs=$IFS
  IFS='
'
  for old_path in $RESULT_PATHS; do
    # Overlapping roots would make duplicate manifest entries and weaken the
    # one-source-file/one-verification invariant.
    case "$new_path/" in "$old_path/"*)
      IFS=$old_ifs
      die "overlapping --result-path values: $old_path and $new_path"
      ;;
    esac
    case "$old_path/" in "$new_path/"*)
      IFS=$old_ifs
      die "overlapping --result-path values: $old_path and $new_path"
      ;;
    esac
  done
  IFS=$old_ifs

  if [ -z "$RESULT_PATHS" ]; then
    RESULT_PATHS=$new_path
  else
    RESULT_PATHS="$RESULT_PATHS
$new_path"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pod-id)
      need_value "$1" "$#"; POD_ID=$2; shift 2 ;;
    --ssh-host)
      need_value "$1" "$#"; SSH_HOST=$2; shift 2 ;;
    --ssh-port)
      need_value "$1" "$#"; SSH_PORT=$2; shift 2 ;;
    --ssh-user)
      need_value "$1" "$#"; SSH_USER=$2; shift 2 ;;
    --ssh-key)
      need_value "$1" "$#"; SSH_KEY=$2; shift 2 ;;
    --remote-workspace)
      need_value "$1" "$#"; REMOTE_WORKSPACE=$2; shift 2 ;;
    --local-destination)
      need_value "$1" "$#"; LOCAL_DESTINATION=$2; shift 2 ;;
    --status-file)
      need_value "$1" "$#"; STATUS_FILE=$2; shift 2 ;;
    --result-path)
      need_value "$1" "$#"; append_result_path "$2"; shift 2 ;;
    --process-pattern)
      need_value "$1" "$#"; PROCESS_PATTERN=$2; shift 2 ;;
    --poll-seconds)
      need_value "$1" "$#"; POLL_SECONDS=$2; shift 2 ;;
    --snapshot-attempts)
      need_value "$1" "$#"; SNAPSHOT_ATTEMPTS=$2; shift 2 ;;
    --snapshot-delay)
      need_value "$1" "$#"; SNAPSHOT_DELAY=$2; shift 2 ;;
    --once)
      ONCE=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "$PROGRAM: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$POD_ID" ] || die "--pod-id is required"
[ -n "$SSH_HOST" ] || die "--ssh-host is required"
[ -n "$LOCAL_DESTINATION" ] || die "--local-destination is required"
[ -n "$PROCESS_PATTERN" ] || die "--process-pattern may not be empty"
case "$LOCAL_DESTINATION" in */) die "--local-destination may not end in /" ;; esac

case "$POD_ID" in *[!A-Za-z0-9._-]*) die "invalid --pod-id: $POD_ID" ;; esac
case "$SSH_USER" in ''|*[!A-Za-z0-9._-]*) die "invalid --ssh-user: $SSH_USER" ;; esac
case "$SSH_HOST" in ''|*[!A-Za-z0-9.:-]*) die "invalid --ssh-host: $SSH_HOST" ;; esac
case "$PROCESS_PATTERN" in
  *[!A-Za-z0-9._/+:-]*) die "invalid --process-pattern: $PROCESS_PATTERN" ;;
esac
require_positive_uint "--ssh-port" "$SSH_PORT"
require_positive_uint "--poll-seconds" "$POLL_SECONDS"
require_positive_uint "--snapshot-attempts" "$SNAPSHOT_ATTEMPTS"
require_uint "--snapshot-delay" "$SNAPSHOT_DELAY"
require_safe_remote_path "--remote-workspace" "$REMOTE_WORKSPACE"
case "$REMOTE_WORKSPACE" in
  /*) ;;
  *) die "--remote-workspace must be absolute" ;;
esac
require_safe_remote_path "--status-file" "$STATUS_FILE"
case "$STATUS_FILE" in
  /*|.|..|*/|*//*) die "--status-file must be a normalized relative path" ;;
esac

if [ -z "$RESULT_PATHS" ]; then
  append_result_path results
fi

if [ -n "$SSH_KEY" ] && [ "$DRY_RUN" -eq 0 ] && [ ! -r "$SSH_KEY" ]; then
  die "SSH key is not readable: $SSH_KEY"
fi
if [ -e "$LOCAL_DESTINATION" ]; then
  die "local destination already exists: $LOCAL_DESTINATION"
fi

TARGET=$SSH_USER@$SSH_HOST
REMOTE_MANIFEST=.metaflip-harvest/$POD_ID-SOURCE_SHA256SUMS

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' \
    "HARVEST_DRY_RUN pod=$POD_ID target=$TARGET port=$SSH_PORT" \
    "  remote_workspace=$REMOTE_WORKSPACE" \
    "  status_file=$STATUS_FILE" \
    "  process_pattern=$PROCESS_PATTERN" \
    "  local_destination=$LOCAL_DESTINATION" \
    "  remote_manifest=$REMOTE_MANIFEST" \
    "  result_paths:"
  old_ifs=$IFS
  IFS='
'
  for path in $RESULT_PATHS; do printf '    %s\n' "$path"; done
  IFS=$old_ifs
  printf '%s\n' \
    "  action=poll, hash-copy-hash, verify, then: runpodctl pod stop $POD_ID" \
    "  no cloud or filesystem commands executed"
  exit 0
fi

command -v "$SSH_CMD" >/dev/null 2>&1 || die "SSH command not found: $SSH_CMD"
command -v "$RSYNC_CMD" >/dev/null 2>&1 || die "rsync command not found: $RSYNC_CMD"
command -v "$RUNPODCTL_CMD" >/dev/null 2>&1 || die "runpodctl command not found: $RUNPODCTL_CMD"
command -v "$SLEEP_CMD" >/dev/null 2>&1 || die "sleep command not found: $SLEEP_CMD"

remote_exec() {
  remote_command=$1
  if [ -n "$SSH_KEY" ]; then
    "$SSH_CMD" -o BatchMode=yes -o ConnectTimeout=15 \
      -i "$SSH_KEY" -p "$SSH_PORT" "$TARGET" "$remote_command"
  else
    "$SSH_CMD" -o BatchMode=yes -o ConnectTimeout=15 \
      -p "$SSH_PORT" "$TARGET" "$remote_command"
  fi
}

shell_quote() {
  # Produce one POSIX-shell word. Remote values currently use a stricter
  # alphabet, but the rsync SSH wrapper also quotes configurable local paths.
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g") || \
    die "could not quote a shell argument"
  printf "'%s'" "$escaped"
}

Q_WORKSPACE=$(shell_quote "$REMOTE_WORKSPACE")
Q_STATUS=$(shell_quote "$STATUS_FILE")
Q_PATTERN=$(shell_quote "$PROCESS_PATTERN")
Q_MANIFEST=$(shell_quote "$REMOTE_MANIFEST")

probe_remote() {
  remote_exec "set -u
cd $Q_WORKSPACE || exit 41
phase=missing
exact_rejects=unknown
if [ -r $Q_STATUS ]; then
  value=\$(sed -n 's/^phase=//p' $Q_STATUS | sed -n '1p')
  [ -z \"\$value\" ] || phase=\$value
  value=\$(sed -n 's/^exact_rejects=//p' $Q_STATUS | sed -n '1p')
  [ -z \"\$value\" ] || exact_rejects=\$value
fi
process=unknown
if command -v pgrep >/dev/null 2>&1; then
  pids=\$(pgrep -f -- $Q_PATTERN 2>/dev/null)
  pgrep_rc=\$?
  if [ \"\$pgrep_rc\" -le 1 ]; then
    process=absent
    for pid in \$pids; do
      # The remote login shell's own command line contains PROCESS_PATTERN as
      # part of this probe. Exclude that shell rather than reporting ourselves.
      if [ \"\$pid\" != \"\$\$\" ]; then process=running; break; fi
    done
  fi
fi
printf 'phase=%s\\nprocess=%s\\nexact_rejects=%s\\n' \
  \"\$phase\" \"\$process\" \"\$exact_rejects\""
}

field_from_probe() {
  field=$1
  body=$2
  printf '%s\n' "$body" | sed -n "s/^$field=//p" | sed -n '1p'
}

terminal_kind() {
  phase=$1
  process=$2
  exact_rejects=$3

  case "$exact_rejects" in
    ''|unknown|0) ;;
    *[!0-9]*) printf '%s\n' failure; return ;;
    *) printf '%s\n' failure; return ;;
  esac
  case "$phase" in
    done) printf '%s\n' success ;;
    failed|failure|error|fatal|oom|exact-reject|aborted|cancelled|canceled)
      printf '%s\n' failure ;;
    *)
      if [ "$process" = absent ]; then
        printf '%s\n' failure
      else
        printf '%s\n' active
      fi
      ;;
  esac
}

poll_number=0
while :; do
  poll_number=$((poll_number + 1))
  if ! probe=$(probe_remote); then
    echo "$PROGRAM: poll $poll_number: SSH/status probe failed; pod left untouched" >&2
    if [ "$ONCE" -eq 1 ]; then exit 1; fi
    "$SLEEP_CMD" "$POLL_SECONDS"
    continue
  fi
  phase=$(field_from_probe phase "$probe")
  process=$(field_from_probe process "$probe")
  exact_rejects=$(field_from_probe exact_rejects "$probe")
  kind=$(terminal_kind "$phase" "$process" "$exact_rejects")
  printf 'HARVEST_POLL pod=%s poll=%s phase=%s process=%s exact_rejects=%s kind=%s\n' \
    "$POD_ID" "$poll_number" "$phase" "$process" "$exact_rejects" "$kind"
  if [ "$kind" != active ]; then break; fi
  if [ "$ONCE" -eq 1 ]; then
    echo "$PROGRAM: campaign remains active; no copy or stop attempted" >&2
    exit 3
  fi
  "$SLEEP_CMD" "$POLL_SECONDS"
done

# Build the quoted find/rsync root list once.  All values passed through this
# string were normalized by require_relative_result_path.
REMOTE_RESULT_ARGS=
old_ifs=$IFS
IFS='
'
for path in $RESULT_PATHS; do
  REMOTE_RESULT_ARGS="$REMOTE_RESULT_ARGS $(shell_quote "$path")"
done
IFS=$old_ifs

generate_remote_manifest() {
  output=$1
  remote_exec "set -eu
cd $Q_WORKSPACE
command -v sha256sum >/dev/null 2>&1 || {
  echo 'remote sha256sum is unavailable' >&2
  exit 42
}
for path in $REMOTE_RESULT_ARGS; do
  [ -e \"\$path\" ] || {
    echo \"missing configured result path: \$path\" >&2
    exit 43
  }
done
special=\$(find $REMOTE_RESULT_ARGS ! -type f ! -type d -print -quit)
if [ -n \"\$special\" ]; then
  echo \"refusing unhashable non-file in result tree: \$special\" >&2
  exit 44
fi
mkdir -p .metaflip-harvest
list=$Q_MANIFEST.list.\$\$
sorted=$Q_MANIFEST.sorted.\$\$
tmp=$Q_MANIFEST.tmp.\$\$
trap 'rm -f \"\$list\" \"\$sorted\" \"\$tmp\"' EXIT HUP INT TERM
find $REMOTE_RESULT_ARGS -type f -print0 > \"\$list\"
LC_ALL=C sort -z \"\$list\" > \"\$sorted\"
if [ -s \"\$sorted\" ]; then
  xargs -0 sha256sum < \"\$sorted\" > \"\$tmp\"
else
  : > \"\$tmp\"
fi
mv -f \"\$tmp\" $Q_MANIFEST
rm -f \"\$list\" \"\$sorted\"
trap - EXIT HUP INT TERM
cat $Q_MANIFEST" > "$output"
}

make_rsync_rsh() {
  wrapper=$1
  {
    printf '%s\n' '#!/bin/sh'
    if [ -n "$SSH_KEY" ]; then
      printf 'exec %s -o BatchMode=yes -o ConnectTimeout=15 -i %s -p %s "$@"\n' \
        "$(shell_quote "$SSH_CMD")" "$(shell_quote "$SSH_KEY")" "$(shell_quote "$SSH_PORT")"
    else
      printf 'exec %s -o BatchMode=yes -o ConnectTimeout=15 -p %s "$@"\n' \
        "$(shell_quote "$SSH_CMD")" "$(shell_quote "$SSH_PORT")"
    fi
  } > "$wrapper"
  chmod 700 "$wrapper"
}

verify_local_manifest() {
  stage=$1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$stage" && sha256sum -c SOURCE_SHA256SUMS)
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    (cd "$stage" && shasum -a 256 -c SOURCE_SHA256SUMS)
    return
  fi
  echo "$PROGRAM: neither sha256sum nor shasum is available locally" >&2
  return 1
}

destination_parent=$(dirname -- "$LOCAL_DESTINATION")
mkdir -p "$destination_parent" || die "cannot create local destination parent"

stable_stage=
attempt=1
while [ "$attempt" -le "$SNAPSHOT_ATTEMPTS" ]; do
  stage=$LOCAL_DESTINATION.partial.$POD_ID.$$.attempt-$attempt
  if [ -e "$stage" ]; then
    die "staging path unexpectedly exists: $stage"
  fi
  mkdir -p "$stage" || die "cannot create staging directory: $stage"
  before=$stage/SOURCE_SHA256SUMS.before
  after=$stage/SOURCE_SHA256SUMS.after

  echo "HARVEST_SNAPSHOT pod=$POD_ID attempt=$attempt/$SNAPSHOT_ATTEMPTS phase=$phase process=$process"
  if ! generate_remote_manifest "$before"; then
    die "source manifest generation failed; pod left untouched (partial: $stage)"
  fi

  rsh_wrapper=$stage/rsync-ssh
  make_rsync_rsh "$rsh_wrapper" || die "could not create rsync SSH wrapper"
  old_ifs=$IFS
  IFS='
'
  for path in $RESULT_PATHS; do
    remote_source=$TARGET:$REMOTE_WORKSPACE/./$path
    if ! "$RSYNC_CMD" -a --relative -e "$rsh_wrapper" \
        "$remote_source" "$stage/"; then
      IFS=$old_ifs
      die "copy failed for $path; pod left untouched (partial: $stage)"
    fi
  done
  IFS=$old_ifs

  if [ "$SNAPSHOT_DELAY" -gt 0 ]; then "$SLEEP_CMD" "$SNAPSHOT_DELAY"; fi
  if ! generate_remote_manifest "$after"; then
    die "post-copy source manifest failed; pod left untouched (partial: $stage)"
  fi
  if ! cmp -s "$before" "$after"; then
    echo "$PROGRAM: source changed during attempt $attempt; retrying without stopping" >&2
    attempt=$((attempt + 1))
    continue
  fi

  cp "$after" "$stage/SOURCE_SHA256SUMS" || \
    die "could not install local manifest; pod left untouched"
  if ! verify_local_manifest "$stage"; then
    die "local hash verification failed; pod left untouched (partial: $stage)"
  fi
  rm -f "$rsh_wrapper" "$before" "$after"
  stable_stage=$stage
  break
done

[ -n "$stable_stage" ] || \
  die "source never stabilized after $SNAPSHOT_ATTEMPTS attempts; pod left untouched"

# Recheck terminal state immediately before publishing the snapshot.  If a
# supervisor restarted the campaign, keep both the pod and verified partial.
if ! final_probe=$(probe_remote); then
  die "final status probe failed; pod left untouched (verified partial: $stable_stage)"
fi
final_phase=$(field_from_probe phase "$final_probe")
final_process=$(field_from_probe process "$final_probe")
final_exact_rejects=$(field_from_probe exact_rejects "$final_probe")
final_kind=$(terminal_kind "$final_phase" "$final_process" "$final_exact_rejects")
if [ "$final_kind" = active ]; then
  die "campaign became active during harvest; pod left untouched (verified partial: $stable_stage)"
fi

{
  printf 'schema=1\n'
  printf 'pod_id=%s\n' "$POD_ID"
  printf 'remote=%s\n' "$TARGET"
  printf 'remote_workspace=%s\n' "$REMOTE_WORKSPACE"
  printf 'phase=%s\n' "$final_phase"
  printf 'terminal_kind=%s\n' "$final_kind"
  printf 'process=%s\n' "$final_process"
  printf 'exact_rejects=%s\n' "$final_exact_rejects"
  printf 'source_manifest=%s\n' "$REMOTE_MANIFEST"
} > "$stable_stage/HARVEST_METADATA"

[ ! -e "$LOCAL_DESTINATION" ] || \
  die "local destination appeared during harvest; pod left untouched (verified partial: $stable_stage)"
if ! mv "$stable_stage" "$LOCAL_DESTINATION"; then
  die "could not publish verified local snapshot; pod left untouched"
fi

printf 'HARVEST_VERIFIED pod=%s destination=%s phase=%s kind=%s\n' \
  "$POD_ID" "$LOCAL_DESTINATION" "$final_phase" "$final_kind"
echo "HARVEST_STOP pod=$POD_ID command=runpodctl-pod-stop"
if ! "$RUNPODCTL_CMD" pod stop "$POD_ID"; then
  die "verified harvest is safe at $LOCAL_DESTINATION, but pod stop failed"
fi
printf 'HARVEST_STOPPED pod=%s destination=%s\n' "$POD_ID" "$LOCAL_DESTINATION"
