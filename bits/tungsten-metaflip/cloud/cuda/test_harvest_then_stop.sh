#!/bin/sh
# Mock-only regression for the host-side harvest-before-stop invariant.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD=$SELF_DIR/harvest_then_stop.sh
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-harvest-guard.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

MOCK_BIN=$TEST_DIR/mock-bin
REMOTE=$TEST_DIR/remote
mkdir -p "$MOCK_BIN" "$REMOTE/results/archive" "$REMOTE/cpu-results-445"

printf '%s\n' \
  'schema=1' \
  'phase=done' \
  'rank=247' \
  'density=3094' \
  'exact_rejects=0' > "$REMOTE/results/status.txt"
printf '%s\n' '7x7 exact best' > "$REMOTE/results/best.txt"
printf '%s\n' 'archived exact endpoint' > "$REMOTE/results/archive/epoch-0007.txt"
printf '%s\n' 'rectangular worker result' > "$REMOTE/cpu-results-445/best.txt"

# Execute the final SSH command locally.  The guard still has to construct a
# valid noninteractive SSH invocation and safe remote shell program.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "ssh %s\n" "$*" >> "$MOCK_SSH_LOG"' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -o|-i|-p) shift 2 ;;' \
  '    *) shift; break ;;' \
  '  esac' \
  'done' \
  '[ "$#" -eq 1 ] || exit 91' \
  'exec sh -c "$1"' > "$MOCK_BIN/ssh"

# Reproduce rsync --relative for the one remote source used per invocation.
printf '%s\n' \
  '#!/bin/sh' \
  'printf "rsync %s\n" "$*" >> "$MOCK_RSYNC_LOG"' \
  'source_path=' \
  'destination=' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -a|--relative) shift ;;' \
  '    -e) shift 2 ;;' \
  '    *)' \
  '      if [ -z "$source_path" ]; then source_path=$1; else destination=$1; fi' \
  '      shift' \
  '      ;;' \
  '  esac' \
  'done' \
  '[ -n "$source_path" ] && [ -n "$destination" ] || exit 92' \
  'remote_path=${source_path#*:}' \
  'relative=${remote_path#*/./}' \
  'mkdir -p "$destination/$(dirname -- "$relative")"' \
  'cp -R "$remote_path" "$destination/$relative"' \
  'if [ "${MOCK_CORRUPT_COPY:-0}" -eq 1 ]; then' \
  '  victim=$(find "$destination/$relative" -type f -print | sed -n "1p")' \
  '  [ -z "$victim" ] || printf "%s\n" CORRUPTED >> "$victim"' \
  'fi' \
  'if [ "${MOCK_MUTATE_SOURCE:-0}" -eq 1 ]; then' \
  '  victim=$(find "$remote_path" -type f -print | sed -n "1p")' \
  '  [ -z "$victim" ] || printf "%s\n" CHANGED >> "$victim"' \
  'fi' > "$MOCK_BIN/rsync"

printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "$*" >> "$MOCK_RUNPODCTL_LOG"' \
  '[ "$#" -eq 3 ] && [ "$1" = pod ] && [ "$2" = stop ]' \
  > "$MOCK_BIN/runpodctl"

# Report a distinct PID so terminal-state tests exercise the stable-snapshot
# branch rather than relying only on process absence.
printf '%s\n' '#!/bin/sh' 'printf "%s\n" 999999' > "$MOCK_BIN/pgrep"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$MOCK_BIN/sleep"
chmod +x "$MOCK_BIN/ssh" "$MOCK_BIN/rsync" "$MOCK_BIN/runpodctl" \
  "$MOCK_BIN/pgrep" "$MOCK_BIN/sleep"

SSH_LOG=$TEST_DIR/ssh.log
RSYNC_LOG=$TEST_DIR/rsync.log
RUNPODCTL_LOG=$TEST_DIR/runpodctl.log
: > "$SSH_LOG"
: > "$RSYNC_LOG"
: > "$RUNPODCTL_LOG"

run_guard() {
  destination=$1
  shift
  PATH="$MOCK_BIN:$PATH" \
    MOCK_SSH_LOG="$SSH_LOG" \
    MOCK_RSYNC_LOG="$RSYNC_LOG" \
    MOCK_RUNPODCTL_LOG="$RUNPODCTL_LOG" \
    METAFLIP_HARVEST_SSH="$MOCK_BIN/ssh" \
    METAFLIP_HARVEST_RSYNC="$MOCK_BIN/rsync" \
    METAFLIP_HARVEST_RUNPODCTL="$MOCK_BIN/runpodctl" \
    METAFLIP_HARVEST_SLEEP="$MOCK_BIN/sleep" \
    sh "$GUARD" \
      --pod-id mockpod --ssh-host mock.example --ssh-port 22022 \
      --remote-workspace "$REMOTE" --local-destination "$destination" \
      --result-path results --result-path cpu-results-445 \
      --snapshot-delay 0 "$@"
}

# Happy path: both result trees and the source manifest must land locally
# before the sole cloud mutation, `pod stop`, is recorded.
GOOD_DEST=$TEST_DIR/good-harvest
run_guard "$GOOD_DEST" > "$TEST_DIR/good.out" 2> "$TEST_DIR/good.err"
test -f "$GOOD_DEST/results/best.txt"
test -f "$GOOD_DEST/results/archive/epoch-0007.txt"
test -f "$GOOD_DEST/cpu-results-445/best.txt"
test -f "$GOOD_DEST/SOURCE_SHA256SUMS"
test -f "$GOOD_DEST/HARVEST_METADATA"
(cd "$GOOD_DEST" && sha256sum -c SOURCE_SHA256SUMS >/dev/null)
grep -qx 'pod stop mockpod' "$RUNPODCTL_LOG"
grep -qx 'phase=done' "$GOOD_DEST/HARVEST_METADATA"
grep -qx 'process=running' "$GOOD_DEST/HARVEST_METADATA"
test -f "$REMOTE/.metaflip-harvest/mockpod-SOURCE_SHA256SUMS"

# A terminal failure is still evidence worth preserving.  It may be stopped,
# but only after the same stable-copy and hash gates.
printf '%s\n' 'schema=1' 'phase=failure' 'exact_rejects=0' \
  > "$REMOTE/results/status.txt"
FAILURE_DEST=$TEST_DIR/failure-harvest
run_guard "$FAILURE_DEST" > "$TEST_DIR/failure.out" 2> "$TEST_DIR/failure.err"
grep -qx 'terminal_kind=failure' "$FAILURE_DEST/HARVEST_METADATA"
test "$(grep -c '^pod stop mockpod$' "$RUNPODCTL_LOG")" -eq 2

# Corrupting one transferred byte must fail open: no published destination and
# no additional runpodctl invocation.
printf '%s\n' 'schema=1' 'phase=done' 'exact_rejects=0' \
  > "$REMOTE/results/status.txt"
CORRUPT_DEST=$TEST_DIR/corrupt-harvest
set +e
MOCK_CORRUPT_COPY=1 run_guard "$CORRUPT_DEST" \
  > "$TEST_DIR/corrupt.out" 2> "$TEST_DIR/corrupt.err"
corrupt_rc=$?
set -e
test "$corrupt_rc" -ne 0
test ! -e "$CORRUPT_DEST"
test "$(grep -c '^pod stop mockpod$' "$RUNPODCTL_LOG")" -eq 2
grep -q 'local hash verification failed; pod left untouched' "$TEST_DIR/corrupt.err"

# A source that changes across every copy never becomes eligible for stop,
# even though each individual rsync invocation succeeds.
CHANGING_DEST=$TEST_DIR/changing-harvest
set +e
MOCK_MUTATE_SOURCE=1 run_guard "$CHANGING_DEST" --snapshot-attempts 2 \
  > "$TEST_DIR/changing.out" 2> "$TEST_DIR/changing.err"
changing_rc=$?
set -e
test "$changing_rc" -ne 0
test ! -e "$CHANGING_DEST"
test "$(grep -c '^pod stop mockpod$' "$RUNPODCTL_LOG")" -eq 2
grep -q 'source never stabilized after 2 attempts; pod left untouched' \
  "$TEST_DIR/changing.err"

# A live nonterminal campaign returns the documented --once code and never
# starts a transfer or cloud mutation.
printf '%s\n' 'schema=1' 'phase=epoch' 'exact_rejects=0' \
  > "$REMOTE/results/status.txt"
ACTIVE_DEST=$TEST_DIR/active-harvest
rsync_before=$(wc -l < "$RSYNC_LOG" | tr -d ' ')
set +e
run_guard "$ACTIVE_DEST" --once > "$TEST_DIR/active.out" 2> "$TEST_DIR/active.err"
active_rc=$?
set -e
test "$active_rc" -eq 3
test ! -e "$ACTIVE_DEST"
test "$(wc -l < "$RSYNC_LOG" | tr -d ' ')" -eq "$rsync_before"
test "$(grep -c '^pod stop mockpod$' "$RUNPODCTL_LOG")" -eq 2

# Dry-run validates and describes the destructive boundary without invoking
# SSH, rsync, sleep, or runpodctl.
DRY_DEST=$TEST_DIR/dry-harvest
ssh_before=$(wc -l < "$SSH_LOG" | tr -d ' ')
PATH="$MOCK_BIN:$PATH" \
  METAFLIP_HARVEST_SSH=/does/not/exist \
  METAFLIP_HARVEST_RSYNC=/does/not/exist \
  METAFLIP_HARVEST_RUNPODCTL=/does/not/exist \
  sh "$GUARD" --pod-id drypod --ssh-host mock.example \
    --remote-workspace "$REMOTE" --local-destination "$DRY_DEST" \
    --result-path results --dry-run > "$TEST_DIR/dry.out"
grep -q 'no cloud or filesystem commands executed' "$TEST_DIR/dry.out"
test "$(wc -l < "$SSH_LOG" | tr -d ' ')" -eq "$ssh_before"
test ! -e "$DRY_DEST"

# The implementation itself must not acquire a terminate/delete vocabulary.
if grep -E 'runpodctl.*(delete|terminate)|pod (delete|remove|rm)' "$GUARD" >/dev/null; then
  echo 'HARVEST_GUARD_TEST destructive pod command found' >&2
  exit 1
fi

printf '%s\n' \
  'CUDA777_HARVEST_GUARD_TEST ok stable=1 failure=preserved corrupt=fail-open changing=fail-open active=untouched dry-run=clean'
