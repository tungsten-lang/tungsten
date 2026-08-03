#!/usr/bin/env sh
set -eu

# E3: whole-loop benchmark — compiled Tungsten vs destination-reusing GMP.
# Builds both halves, runs each workload REPS times per lane (min wins,
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
"$ROOT/bin/tungsten" -o "$DIR/program_loops" --release "$DIR/program_loops.w" >/dev/null
# shellcheck disable=SC2086
"$CC" -O3 -mcpu=native $GMP_CFLAGS "$DIR/program_loops_gmp.c" $GMP_LDFLAGS \
  -o "$DIR/program_loops_gmp"

run_lane() {
  # $1 binary, $2 workload -> "ns checksum" (min ns across REPS)
  best=""
  best_check=""
  r=0
  while [ "$r" -lt "$REPS" ]; do
    line=$("$1" "$2")
    ns=$(printf '%s' "$line" | cut -f3)
    check=$(printf '%s' "$line" | cut -f4)
    if [ -z "$best" ] || [ "$(printf '%s %s\n' "$ns" "$best" | awk '{print ($1 < $2) ? 1 : 0}')" = 1 ]; then
      best=$ns
      best_check=$check
    fi
    r=$((r + 1))
  done
  printf '%s %s\n' "$best" "$best_check"
}

printf '%-12s %14s %14s %8s\n' "workload" "tungsten ns/it" "gmp ns/it" "T/G"
fail=0
for workload in accumulate mulchain addchain; do
  # Alternate which lane goes first across workloads.
  if [ $((fail % 2)) -eq 0 ]; then
    t_out=$(run_lane "$DIR/program_loops" "$workload")
    g_out=$(run_lane "$DIR/program_loops_gmp" "$workload")
  else
    g_out=$(run_lane "$DIR/program_loops_gmp" "$workload")
    t_out=$(run_lane "$DIR/program_loops" "$workload")
  fi
  t_ns=${t_out% *}; t_check=${t_out#* }
  g_ns=${g_out% *}; g_check=${g_out#* }
  if [ "$t_check" != "$g_check" ]; then
    echo "CHECKSUM MISMATCH on $workload: tungsten=$t_check gmp=$g_check" >&2
    exit 1
  fi
  ratio=$(printf '%s %s\n' "$t_ns" "$g_ns" | awk '{printf "%.2f", $1 / $2}')
  printf '%-12s %14s %14s %8s\n' "$workload" "$t_ns" "$g_ns" "$ratio"
done
echo
echo "Idiomatic loops: Tungsten allocates a fresh value per pass; GMP reuses"
echo "its mpz destination. This ratio, not the per-op matrix, is the"
echo "whole-program story (and the E4 mutate-if-unique payoff meter)."
