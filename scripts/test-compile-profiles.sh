#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="${REAL_CC:-$(command -v clang)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-compile-profiles.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

printf '<< "profile probe"\n' >"$TMP/probe.w"
cat >"$TMP/trace-cc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TRACE_FILE"
exec "$REAL_CC" "$@"
SH
chmod +x "$TMP/trace-cc"

check_profile() {
  local name="$1"
  local expected="$2"
  local forbidden="$3"
  shift 3
  local trace="$TMP/$name.trace"
  local output="$TMP/$name"
  : >"$trace"
  TRACE_FILE="$trace" REAL_CC="$REAL_CC" \
    TUNGSTEN_CC="$TMP/trace-cc" \
    TUNGSTEN_CACHE_DIR="$TMP/cache-$name" \
    TUNGSTEN_INCREMENTAL=0 \
    "$COMPILER" compile --no-lto "$@" --out "$output" "$TMP/probe.w" \
    >"$TMP/$name.build"

  local link
  link="$(tail -n 1 "$trace")"
  if ! grep -Eq "(^| )${expected}( |$)" <<<"$link"; then
    printf '%s compile did not use %s:\n%s\n' "$name" "$expected" "$link" >&2
    exit 1
  fi
  if grep -Eq "(^| )${forbidden}( |$)" <<<"$link"; then
    printf '%s compile unexpectedly used %s:\n%s\n' "$name" "$forbidden" "$link" >&2
    exit 1
  fi
  [[ "$($output)" == "profile probe" ]]
}

check_profile default -O3 -O0
check_profile dev -O0 -O3 --dev

# `compile-batch` has its own positional-file pass. Keep --dev out of that file
# list and prove the batch linker selects the same explicit O0 profile.
: >"$TMP/batch.trace"
TRACE_FILE="$TMP/batch.trace" REAL_CC="$REAL_CC" \
  TUNGSTEN_CC="$TMP/trace-cc" \
  TUNGSTEN_CACHE_DIR="$TMP/cache-batch" \
  TUNGSTEN_INCREMENTAL=0 \
  "$COMPILER" compile-batch --dev --no-lto "$TMP/probe.w" \
  >"$TMP/batch.build"
batch_link="$(tail -n 1 "$TMP/batch.trace")"
grep -Eq '(^| )-O0( |$)' <<<"$batch_link"
[[ -x "$TMP/probe.wc" ]]
[[ "$("$TMP/probe.wc")" == "profile probe" ]]

if "$COMPILER" compile --dev --release --out "$TMP/conflict" "$TMP/probe.w" \
    >"$TMP/conflict.out" 2>&1; then
  printf 'compile accepted mutually exclusive --dev and --release\n' >&2
  exit 1
fi
grep -q -- '--dev and --release are mutually exclusive' "$TMP/conflict.out"

printf 'compile profile contracts: PASS\n'
