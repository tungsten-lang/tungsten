#!/usr/bin/env bash
# Best-of-N stage-1 self-compile bench. Captures wallclock, cycles, and peak
# RSS for the same `tungsten-c compile` invocation that `bin/tungsten build`
# runs at Stage 1, so the bench numbers correspond to what users see in the
# build output.
#
# Runs from project root with --out + --release, so the compiler reaches the
# `Built [out_path]` exit (i.e. lowering + IR + emit + link all happen, even
# if some bits are stubbed). An earlier version ran from
# implementations/c/ with no --out and timed an aborted compile that failed
# at the resolve_runtime_dir ccall, undercounting by 5-6×.
#
# Usage:
#   bench/c-vm-perf.sh                  # 15 runs, append to ledger
#   N=5 bench/c-vm-perf.sh              # 5 runs
#   LABEL="commit X" bench/c-vm-perf.sh # custom label
#   NO_LEDGER=1 bench/c-vm-perf.sh      # print only

set -euo pipefail

# Resolve all paths up-front, then chdir to project root for the actual
# invocations (the compiler hardcodes some lookups against cwd).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LEDGER_DEFAULT="$SCRIPT_DIR/c-vm-perf.md"

N="${N:-15}"
BIN="${BIN:-$ROOT/implementations/c/build/tungsten-c}"
COMPILER="${COMPILER:-$ROOT/compiler/tungsten.w}"
TABLE="${TABLE:-$ROOT/languages/tungsten/tungsten.lex64}"
LEDGER="${LEDGER:-$LEDGER_DEFAULT}"
LABEL="${LABEL:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) — $(git -C "$ROOT" log -1 --format=%s 2>/dev/null | head -c 60)}"
OUT_BIN="${OUT_BIN:-/tmp/tungsten-bench.wc}"
LL_DIR="${LL_DIR:-/tmp/tungsten-bench-ll}"

mkdir -p "$LL_DIR"
cd "$ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "bench: $BIN not found; running make..." >&2
  make -C "$ROOT/implementations/c" >&2
fi

best_real=""; best_user=""; best_cycles=""; best_rss=""

RUNTIME_ARCHIVE="${RUNTIME_ARCHIVE:-/tmp/tungsten-runtime.a}"

# If the runtime archive is missing, run a one-off `bin/tungsten build -1`
# to populate it. Otherwise the bench would charge stage 1 for the runtime
# rebuild — which is exactly what `bin/tungsten build` skips via cache.
if [[ ! -f "$RUNTIME_ARCHIVE" ]]; then
  echo "bench: runtime archive missing at $RUNTIME_ARCHIVE; running 'bin/tungsten build -1' to populate..." >&2
  bin/tungsten build -1 >/dev/null 2>&1 || true
fi

for i in $(seq 1 "$N"); do
  out=$(TUNGSTEN_LEX64_TABLE="$TABLE" \
        TUNGSTEN_LL_DIR="$LL_DIR" \
        TUNGSTEN_LL_PATH="$LL_DIR/stage1-c.ll" \
        /usr/bin/time -l "$BIN" "$COMPILER" compile "$COMPILER" --out "$OUT_BIN" --release \
                            --runtime "$RUNTIME_ARCHIVE" --no-lto 2>&1 || true)
  real=$(awk '/real/ { print $1; exit }' <<<"$out")
  user=$(awk '/real/ { print $3; exit }' <<<"$out")
  cycles=$(awk '/cycles elapsed/ { print $1; exit }' <<<"$out")
  rss=$(awk '/maximum resident set size/ { print $1; exit }' <<<"$out")

  if [[ -z "$best_real" ]] || awk -v a="$real" -v b="$best_real" 'BEGIN { exit (a < b) ? 0 : 1 }'; then
    best_real="$real"; best_user="$user"; best_cycles="$cycles"; best_rss="$rss"
  fi
done

# Pretty-print: real seconds, user seconds, cycles in G, peak RSS in MB.
rss_mb=$(awk -v r="$best_rss" 'BEGIN { printf "%.0f", r/1024/1024 }')
cycles_g=$(awk -v c="$best_cycles" 'BEGIN { printf "%.2f", c/1e9 }')

printf 'best of %d:\n' "$N"
printf '  wallclock : %ss\n' "$best_real"
printf '  user      : %ss\n' "$best_user"
printf '  cycles    : %s G\n' "$cycles_g"
printf '  peak RSS  : %s MB\n' "$rss_mb"

if [[ "${NO_LEDGER:-}" == "1" ]]; then
  exit 0
fi

if [[ ! -f "$LEDGER" ]]; then
  cat >"$LEDGER" <<'HDR'
# C VM perf ledger

Best-of-N timings for `tungsten-c compile compiler/tungsten.w --out ... --release`,
i.e. the same stage-1 invocation `bin/tungsten build` runs. Captured by
`bench/c-vm-perf.sh`. Numbers should track the `built  stage1 <ms>` line in
build output.

| date | label | wallclock | cycles | peak RSS |
|------|-------|-----------|--------|----------|
HDR
fi

date_iso=$(date '+%Y-%m-%d %H:%M')
printf '| %s | %s | %ss | %sG | %s MB |\n' "$date_iso" "$LABEL" "$best_real" "$cycles_g" "$rss_mb" >> "$LEDGER"
echo "→ appended to $LEDGER"
