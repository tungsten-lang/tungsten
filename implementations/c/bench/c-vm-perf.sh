#!/usr/bin/env bash
# Median/minimum stage-1 self-compile bench. Captures wallclock, cycles, and
# peak RSS for the same `tungsten-c compile` invocation that `bin/tungsten
# build` runs at Stage 1, so the bench numbers correspond to what users see
# in the build output.
#
# Runs from project root with a fresh --out/LLVM path for every sample,
# --native, --no-lto, and TUNGSTEN_CLANG_OPT=-O0. That prevents the output
# freshness shortcut from turning later samples into no-ops and matches the
# production C-VM stage-1 build. An earlier version ran from
# implementations/c/ with no --out and timed an aborted compile that failed
# at the resolve_runtime_dir ccall, undercounting by 5-6×.
#
# Usage:
#   bench/c-vm-perf.sh                  # 15 runs, append to ledger
#   N=5 bench/c-vm-perf.sh              # 5 runs
#   LABEL="commit X" bench/c-vm-perf.sh # custom label
#   NO_LEDGER=1 bench/c-vm-perf.sh      # print only

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bench: macOS is required (/usr/bin/time -l cycles/RSS metrics)" >&2
  exit 2
fi

# Resolve all paths up-front, then chdir to project root for the actual
# invocations (the compiler hardcodes some lookups against cwd).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LEDGER_DEFAULT="$SCRIPT_DIR/c-vm-perf.md"

N="${N:-15}"
if [[ ! "$N" =~ ^[1-9][0-9]*$ ]]; then
  echo "bench: N must be a positive integer (got '$N')" >&2
  exit 2
fi
BIN="${BIN:-}"
COMPILER="${COMPILER:-$ROOT/compiler/tungsten.w}"
TABLE="${TABLE:-$ROOT/languages/tungsten/tungsten.lex64}"
LEDGER="${LEDGER:-$LEDGER_DEFAULT}"
LABEL="${LABEL:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) — $(git -C "$ROOT" log -1 --format=%s 2>/dev/null | head -c 60)}"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-c-vm-perf.XXXXXX")"
RUN_TAG="$(basename "$RUN_DIR")"
OUT_BIN="${OUT_BIN:-$RUN_DIR/tungsten-bench.wc}"
LL_DIR="${LL_DIR:-$RUN_DIR/ll}"

cleanup() {
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

mkdir -p "$LL_DIR"
cd "$ROOT"

# Prepare the exact content-addressed stage0/runtime configuration through the
# production driver. This is setup work and is not included in any sample.
build_manifest="$RUN_DIR/build.manifest"
TUNGSTEN_BUILD_MANIFEST="$build_manifest" bin/tungsten build -1 >/dev/null
[[ -f "$build_manifest" ]] || {
  echo "bench: production build did not publish $build_manifest" >&2
  exit 1
}
manifest_schema=""
manifest_bin=""
manifest_runtime=""
manifest_env=""
manifest_line_no=0
while IFS= read -r manifest_line; do
  manifest_line_no=$((manifest_line_no + 1))
  case "$manifest_line_no" in
    1) manifest_schema="$manifest_line" ;;
    2) manifest_bin="$manifest_line" ;;
    3) manifest_runtime="$manifest_line" ;;
    4) manifest_env="$manifest_line"; break ;;
  esac
done < "$build_manifest"
[[ "$manifest_schema" == "tungsten-build-manifest-v1" &&
    -n "$manifest_bin" && -n "$manifest_runtime" && -n "$manifest_env" ]] || {
  echo "bench: invalid production build manifest at $build_manifest" >&2
  exit 1
}
if [[ -z "$BIN" ]]; then BIN="$manifest_bin"; fi
[[ -x "$BIN" ]] || {
  echo "bench: stage0 binary missing at $BIN" >&2
  exit 1
}

best_real=""; best_user=""; best_cycles=""; best_rss=""
real_values=(); user_values=(); cycles_values=(); rss_values=()

RUNTIME_ARCHIVE="${RUNTIME_ARCHIVE:-}"
RUNTIME_ENV_MANIFEST="${RUNTIME_ENV_MANIFEST:-}"
if [[ -z "$RUNTIME_ARCHIVE" ]]; then
  RUNTIME_ARCHIVE="$manifest_runtime"
  if [[ -z "$RUNTIME_ENV_MANIFEST" ]]; then
    RUNTIME_ENV_MANIFEST="$manifest_env"
  fi
elif [[ -z "$RUNTIME_ENV_MANIFEST" ]]; then
  if [[ "$RUNTIME_ARCHIVE" == "$manifest_runtime" ]]; then
    RUNTIME_ENV_MANIFEST="$manifest_env"
  else
    echo "bench: custom RUNTIME_ARCHIVE requires matching RUNTIME_ENV_MANIFEST" >&2
    exit 2
  fi
fi
[[ -f "$RUNTIME_ARCHIVE" ]] || {
  echo "bench: runtime archive missing at $RUNTIME_ARCHIVE" >&2
  exit 1
}

env_manifest="$RUNTIME_ENV_MANIFEST"
[[ -f "$env_manifest" ]] || {
  echo "bench: production build did not publish $env_manifest" >&2
  exit 1
}
env_schema=""
zstd_cflags=""
zstd_ldflags=""
onig_cflags=""
onig_ldflags=""
build_os=""
build_cc=""
build_ar=""
build_ranlib=""
env_line_no=0
while IFS= read -r env_line; do
  env_line_no=$((env_line_no + 1))
  case "$env_line_no" in
    1) env_schema="$env_line" ;;
    2) zstd_cflags="$env_line" ;;
    3) zstd_ldflags="$env_line" ;;
    4) onig_cflags="$env_line" ;;
    5) onig_ldflags="$env_line" ;;
    6) build_os="$env_line" ;;
    7) build_cc="$env_line" ;;
    8) build_ar="$env_line" ;;
    9) build_ranlib="$env_line"; break ;;
  esac
done < "$env_manifest"
[[ "$env_schema" == "runtime-env-v1" && -n "$build_os" &&
    -n "$build_cc" && -n "$build_ar" ]] || {
  echo "bench: invalid runtime environment manifest at $env_manifest" >&2
  exit 1
}

for i in $(seq 1 "$N"); do
  # Both paths are unique to this script invocation and sample. Reusing the
  # old fixed paths let the compiler's freshness check skip almost all work.
  run_out="${OUT_BIN}.${RUN_TAG}.${i}"
  run_ll_dir="${LL_DIR}/${RUN_TAG}.${i}"
  run_ll="${run_ll_dir}/stage1-c.ll"
  mkdir -p "$run_ll_dir"

  set +e
  out=$(TUNGSTEN_LEX64_TABLE="$TABLE" \
        TUNGSTEN_ROOT="$ROOT" \
        TUNGSTEN_C_FAST_PARSE=0 \
        TUNGSTEN_ZSTD_CFLAGS="$zstd_cflags" \
        TUNGSTEN_ZSTD_LDFLAGS="$zstd_ldflags" \
        TUNGSTEN_ONIG_CFLAGS="$onig_cflags" \
        TUNGSTEN_ONIG_LDFLAGS="$onig_ldflags" \
        TUNGSTEN_OS="$build_os" \
        TUNGSTEN_CC="$build_cc" \
        TUNGSTEN_AR="$build_ar" \
        TUNGSTEN_RANLIB="$build_ranlib" \
        TUNGSTEN_LL_DIR="$run_ll_dir" \
        TUNGSTEN_LL_PATH="$run_ll" \
        TUNGSTEN_CLANG_OPT=-O0 \
        /usr/bin/time -l "$BIN" "$COMPILER" compile "$COMPILER" --out "$run_out" --native \
                            --runtime "$RUNTIME_ARCHIVE" --no-lto 2>&1)
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    echo "bench: sample $i failed with status $status" >&2
    exit "$status"
  fi

  real=$(awk '/real/ { print $1; exit }' <<<"$out")
  user=$(awk '/real/ { print $3; exit }' <<<"$out")
  cycles=$(awk '/cycles elapsed/ { print $1; exit }' <<<"$out")
  rss=$(awk '/maximum resident set size/ { print $1; exit }' <<<"$out")

  if [[ -z "$real" || -z "$user" || -z "$cycles" || -z "$rss" ]]; then
    printf '%s\n' "$out" >&2
    echo "bench: sample $i did not produce all expected /usr/bin/time metrics" >&2
    exit 1
  fi

  real_values+=("$real")
  user_values+=("$user")
  cycles_values+=("$cycles")
  rss_values+=("$rss")

  if [[ -z "$best_real" ]] || awk -v a="$real" -v b="$best_real" 'BEGIN { exit (a < b) ? 0 : 1 }'; then
    best_real="$real"; best_user="$user"; best_cycles="$cycles"; best_rss="$rss"
  fi
done

# Sort numeric samples and average the middle pair for an even-sized run.
median() {
  printf '%s\n' "$@" | sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2) print values[(NR + 1) / 2]
      else print (values[NR / 2] + values[NR / 2 + 1]) / 2
    }
  '
}

median_real=$(median "${real_values[@]}")
median_user=$(median "${user_values[@]}")
median_cycles=$(median "${cycles_values[@]}")
median_rss=$(median "${rss_values[@]}")

# Pretty-print: real seconds, user seconds, cycles in G, peak RSS in MB.
median_real_fmt=$(awk -v n="$median_real" 'BEGIN { printf "%.2f", n }')
median_user_fmt=$(awk -v n="$median_user" 'BEGIN { printf "%.2f", n }')
median_cycles_g=$(awk -v n="$median_cycles" 'BEGIN { printf "%.2f", n/1e9 }')
median_rss_mb=$(awk -v n="$median_rss" 'BEGIN { printf "%.0f", n/1024/1024 }')
best_real_fmt=$(awk -v n="$best_real" 'BEGIN { printf "%.2f", n }')
best_user_fmt=$(awk -v n="$best_user" 'BEGIN { printf "%.2f", n }')
best_cycles_g=$(awk -v n="$best_cycles" 'BEGIN { printf "%.2f", n/1e9 }')
best_rss_mb=$(awk -v n="$best_rss" 'BEGIN { printf "%.0f", n/1024/1024 }')

printf 'median of %d:\n' "$N"
printf '  wallclock : %ss\n' "$median_real_fmt"
printf '  user      : %ss\n' "$median_user_fmt"
printf '  cycles    : %s G\n' "$median_cycles_g"
printf '  peak RSS  : %s MB\n' "$median_rss_mb"
printf 'minimum wallclock of %d:\n' "$N"
printf '  wallclock : %ss\n' "$best_real_fmt"
printf '  user      : %ss\n' "$best_user_fmt"
printf '  cycles    : %s G\n' "$best_cycles_g"
printf '  peak RSS  : %s MB\n' "$best_rss_mb"

if [[ "${NO_LEDGER:-}" == "1" ]]; then
  exit 0
fi

if [[ ! -f "$LEDGER" ]]; then
  cat >"$LEDGER" <<'HDR'
# C VM perf ledger

Median/minimum timings for `tungsten-c compile compiler/tungsten.w --out ...
--native`, i.e. the same stage-1 invocation `bin/tungsten build` runs.
Captured by `bench/c-vm-perf.sh`. Numbers should track the `built  stage1
<ms>` line in build output. User/cycles/RSS are from the minimum-wallclock
sample.

| date | label | wallclock | user | cycles | peak RSS |
|------|-------|-----------|------|--------|----------|
HDR
fi

date_iso=$(date '+%Y-%m-%d %H:%M')
printf '| %s | %s | median %ss / min %ss | %ss | %sG | %s MB |\n' \
  "$date_iso" "$LABEL" "$median_real_fmt" "$best_real_fmt" "$best_user_fmt" "$best_cycles_g" "$best_rss_mb" >> "$LEDGER"
echo "→ appended to $LEDGER"
