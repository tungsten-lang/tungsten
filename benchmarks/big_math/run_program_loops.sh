#!/usr/bin/env sh
set -eu

# E3: whole-loop benchmark — compiled Tungsten vs destination-reusing GMP.
# Builds both halves, runs each workload REPS times per lane (median with IQR,
# alternating lane order), cross-checks the checksums, prints T/G ratios.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
CC=${CC:-clang}
REPS=${REPS:-5}

GMP_CFLAGS=$(pkg-config --cflags gmp 2>/dev/null || true)
GMP_LDFLAGS=$(pkg-config --libs gmp 2>/dev/null || true)
if [ -z "$GMP_LDFLAGS" ]; then
  echo "GMP is required (pkg-config gmp failed)." >&2
  exit 1
fi

# --release: the default dev link uses the -O0 runtime archive
# (build.rb profile_cflags), which runs intrinsics-based kernels (the
# NEON hybrid add) up to 30x slow — asm kernels hide this, the addchain
# lane exposed it. The GMP twin builds -O3; the lanes must match.
"$ROOT/bin/tungsten" -o "$DIR/program_loops" --release --native --fast \
  "$DIR/program_loops.w" >/dev/null
# shellcheck disable=SC2086
"$CC" -O3 -mcpu=native $GMP_CFLAGS "$DIR/program_loops_gmp.c" $GMP_LDFLAGS \
  -o "$DIR/program_loops_gmp"

sample_stats() {
  # $1 newline-separated timings -> "median_ns iqr_ns"
  printf '%b' "$1" | sort -n | awk '
    function quantile(p, pos, lo, hi, frac) {
      pos = 1 + (n - 1) * p
      lo = int(pos)
      hi = lo < n ? lo + 1 : lo
      frac = pos - lo
      return v[lo] + (v[hi] - v[lo]) * frac
    }
    { v[NR] = $1 }
    END {
      n = NR
      printf "%.9f %.9f", quantile(0.5), quantile(0.75) - quantile(0.25)
    }'
}

run_pair() {
  # $1 workload, $2 initial lane order, $3 optional limbs ->
  # "t_median t_iqr t_checksum g_median g_iqr g_checksum"
  workload=$1
  first=$2
  limbs=${3:-}
  t_samples=""
  g_samples=""
  t_expected=""
  g_expected=""
  r=0
  while [ "$r" -lt "$REPS" ]; do
    if [ $(((r + first) % 2)) -eq 0 ]; then
      t_line=$("$DIR/program_loops" "$workload" 0 ${limbs:+"$limbs"})
      g_line=$("$DIR/program_loops_gmp" "$workload" 0 ${limbs:+"$limbs"})
    else
      g_line=$("$DIR/program_loops_gmp" "$workload" 0 ${limbs:+"$limbs"})
      t_line=$("$DIR/program_loops" "$workload" 0 ${limbs:+"$limbs"})
    fi
    t_ns=$(printf '%s' "$t_line" | cut -f3)
    t_check=$(printf '%s' "$t_line" | cut -f4)
    g_ns=$(printf '%s' "$g_line" | cut -f3)
    g_check=$(printf '%s' "$g_line" | cut -f4)
    if [ -z "$t_expected" ]; then
      t_expected=$t_check
      g_expected=$g_check
    elif [ "$t_check" != "$t_expected" ] || [ "$g_check" != "$g_expected" ]; then
      echo "NONDETERMINISTIC CHECKSUM on $workload" >&2
      exit 1
    fi
    t_samples="${t_samples}${t_ns}\n"
    g_samples="${g_samples}${g_ns}\n"
    r=$((r + 1))
  done
  t_stats=$(sample_stats "$t_samples")
  g_stats=$(sample_stats "$g_samples")
  printf '%s %s %s %s\n' "$t_stats" "$t_expected" "$g_stats" "$g_expected"
}

printf '%-12s %14s %12s %14s %12s %8s\n' \
  "workload" "tungsten med" "tungsten IQR" "gmp med" "gmp IQR" "T/G"
order=0
for workload in accumulate mulchain addchain subchain divchain; do
  pair=$(run_pair "$workload" "$order")
  set -- $pair
  t_ns=$1; t_iqr=$2; t_check=$3
  g_ns=$4; g_iqr=$5; g_check=$6
  if [ "$t_check" != "$g_check" ]; then
    echo "CHECKSUM MISMATCH on $workload: tungsten=$t_check gmp=$g_check" >&2
    exit 1
  fi
  ratio=$(printf '%s %s\n' "$t_ns" "$g_ns" | awk '{printf "%.2f", $1 / $2}')
  printf '%-12s %14s %12s %14s %12s %8s\n' \
    "$workload" "$t_ns" "$t_iqr" "$g_ns" "$g_iqr" "$ratio"
  order=$((order + 1))
done
# pow2 strength-reduction, sign-test, and fused multiply-accumulate lanes.
for lane in "divp2chain:64 512 4096" "modp2chain:64 512 4096" \
            "sgnchain:2 64 4096" "addmulchain:2 8 64"; do
  workload=${lane%%:*}
  for limbs in ${lane#*:}; do
    pair=$(run_pair "$workload" "$order" "$limbs")
    set -- $pair
    t_ns=$1; t_iqr=$2; t_check=$3
    g_ns=$4; g_iqr=$5; g_check=$6
    if [ "$t_check" != "$g_check" ]; then
      echo "CHECKSUM MISMATCH on $workload$limbs: tungsten=$t_check gmp=$g_check" >&2
      exit 1
    fi
    ratio=$(printf '%s %s\n' "$t_ns" "$g_ns" | awk '{printf "%.2f", $1 / $2}')
    printf '%-14s %14s %12s %14s %12s %8s\n' \
      "$workload$limbs" "$t_ns" "$t_iqr" "$g_ns" "$g_iqr" "$ratio"
    order=$((order + 1))
  done
done
# Word-overwrite lanes (E4 stage 3) at the mul1@2/4/32 parity widths.
for workload in wordadd wordsub wordmul wordchain; do
  for limbs in 2 4 32; do
    pair=$(run_pair "$workload" "$order" "$limbs")
    set -- $pair
    t_ns=$1; t_iqr=$2; t_check=$3
    g_ns=$4; g_iqr=$5; g_check=$6
    if [ "$t_check" != "$g_check" ]; then
      echo "CHECKSUM MISMATCH on $workload$limbs: tungsten=$t_check gmp=$g_check" >&2
      exit 1
    fi
    ratio=$(printf '%s %s\n' "$t_ns" "$g_ns" | awk '{printf "%.2f", $1 / $2}')
    printf '%-12s %14s %12s %14s %12s %8s\n' \
      "$workload$limbs" "$t_ns" "$t_iqr" "$g_ns" "$g_iqr" "$ratio"
    order=$((order + 1))
  done
done
echo
echo "Idiomatic loops: GMP reuses its mpz destination; Tungsten may reuse a"
echo "proven-dead unique accumulator, otherwise it falls back to immutable"
echo "result churn. These ratios are the mutate-if-unique acceptance meter."
