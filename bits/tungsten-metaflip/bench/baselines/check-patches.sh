#!/bin/sh
# check-patches.sh [N]: the instrumentation patches leave the search unchanged.
#
# Builds the unmodified programs from the pinned clones (for km2022 additionally a copy whose only change is the seed
# hook, because the program takes its seed from the clock) and compares them with the instrumented binaries of build.sh
# under equal seeds 1..N (default 20):
#   km2024  the line printed by the program and the steps in its log, split off and on, 3x3x3 and 3x3x4; and KM_LOOP=1
#           (walks 0, 1, ... with the seeds seed + 1000003 k in one process) against separate processes with those seeds
#   km2022  the same, 3x3x3 and 2x3x3
#   tfg     the first 40 runner rows of the per-round report (4 runners, rounds of 100000 iterations), 3x3x3 and 3x3x4
# Prints "identical / compared" per program.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
SOTA_SRC=${SOTA_SRC:-$HOME/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota}
SOTA_BUILD=${SOTA_BUILD:-$SOTA_SRC/build}
CXX=${CXX:-/opt/homebrew/opt/llvm/bin/clang++}
OMP_PREFIX=${OMP_PREFIX:-$(cd "$(dirname "$CXX")/.." && pwd)}
N=${1:-20}
adapters=$here/adapters
bin=$SOTA_BUILD/bin
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-patches.XXXXXX")
trap 'find "$tmp" -depth -delete' EXIT
CPU=apple-m5
"$CXX" -mcpu=$CPU -fsyntax-only -x c++ /dev/null 2> /dev/null || CPU=native
FLAGS="-O3 -flto -mcpu=$CPU -std=c++17 -DNDEBUG"
export LC_ALL=C GIT_NO_LAZY_FETCH=1 OMP_NUM_THREADS=1

limit=
command -v timeout > /dev/null 2>&1 && limit="timeout -s KILL 5" # a backstop; the pipe to head ends the program

copy() { mkdir -p "$2" && (cd "$1" && tar --exclude=.git -cf - .) | (cd "$2" && tar -xf -); }

copy "$SOTA_SRC/flips/updated_code" "$tmp/km2024"
(cd "$tmp/km2024" && "$CXX" $FLAGS -o flip main_mm.cpp tensor.cpp mm.cpp pairSet.cpp)
copy "$SOTA_SRC/flips/code" "$tmp/km2022"
(cd "$tmp/km2022" && sed 's|^  long seed = (long)ts.tv_nsec;$|&\n  if(getenv("KM_SEED")) seed = strtol(getenv("KM_SEED"), NULL, 10);|' main.cpp > main.new && mv main.new main.cpp \
  && "$CXX" $FLAGS -o flip scheme.cpp randompath.cpp main.cpp)
copy "$SOTA_SRC/tfg" "$tmp/tfg"
(cd "$tmp/tfg" && make -s -j4 flip_graph CXX="$CXX" FLAGS="$FLAGS -Wno-unused-command-line-argument -fopenmp -I$(ls -d "$OMP_PREFIX"/lib/clang/*/include | head -1) -L$OMP_PREFIX/lib -Wl,-rpath,$OMP_PREFIX/lib" > /dev/null)

std() { # n m p -> .exp of the standard algorithm
  awk -v n="$1" -v m="$2" -v p="$3" -f "$adapters/mfw-lib.awk" -f "$adapters/std2mfw.awk" | awk -f "$adapters/mfw-lib.awk" -f "$adapters/mfw2exp.awk"
}

report() { echo "$1: $2 identical of $3 compared"; }

# km2024
same=0 total=0
for shape in "3 3 3" "3 3 4"; do
  # shellcheck disable=SC2086
  set -- $shape
  std "$1" "$2" "$3" > "$tmp/std.exp"
  for split in 0 1; do
    s=1
    while [ "$s" -le "$N" ]; do
      for v in orig new; do
        d=$tmp/km2024.$v
        mkdir -p "$d" && (cd "$d" && find . -type f -delete)
        prog=$tmp/km2024/flip
        [ "$v" = new ] && prog=$bin/km2024_flip
        (cd "$d" && "$prog" "$tmp/std.exp" "$1" "$2" "$3" 100000 "$split" 1 10 1 "$s" 2> /dev/null | cut -d, -f2 > out.txt; cut -d, -f5,6 k00.log >> out.txt)
      done
      total=$((total + 1))
      cmp -s "$tmp/km2024.orig/out.txt" "$tmp/km2024.new/out.txt" && same=$((same + 1))
      s=$((s + 1))
    done
  done
done
report km2024 "$same" "$total"

# km2024, KM_LOOP=1: the walks of one process equal the walks of separate processes
same=0 total=0
std 3 3 3 > "$tmp/std.exp"
s=1
while [ "$s" -le "$N" ]; do
  d=$tmp/km2024.new
  mkdir -p "$d" && (cd "$d" && find . -type f -delete)
  (cd "$d" && KM_LOOP=1 KM_TARGET_RANK=23 "$bin/km2024_flip" "$tmp/std.exp" 3 3 3 3000 1 1 10 1 "$s" 2> /dev/null > out.txt)
  d=$tmp/km2024.orig
  mkdir -p "$d" && (cd "$d" && find . -type f -delete)
  (cd "$d" && k=0 && while :; do
      seed=$(((s + k * 1000003) % 2147483646))
      line=$("$tmp/km2024/flip" "$tmp/std.exp" 3 3 3 3000 1 1 10 1 "$seed" 2> /dev/null)
      echo "$line" >> out.txt
      [ "${line#*,}" -le 23 ] && break
      k=$((k + 1))
    done)
  total=$((total + 1))
  # the schemes of all walks but the last are equal; the last walk stops at the target in the instrumented program
  # and runs to the end of its path in the unmodified one, so only its rank is compared
  a=$(awk 'NR > 1 { print prev } { prev = $0 }' "$tmp/km2024.orig/out.txt"; awk -F, 'END { print $2 }' "$tmp/km2024.orig/out.txt")
  b=$(awk 'NR > 1 { print prev } { prev = $0 }' "$tmp/km2024.new/out.txt"; awk -F, 'END { print $2 }' "$tmp/km2024.new/out.txt")
  [ "$a" = "$b" ] && same=$((same + 1))
  s=$((s + 1))
done
report "km2024 (KM_LOOP)" "$same" "$total"

# km2022
same=0 total=0
for shape in "3 3 3" "2 3 3"; do
  # shellcheck disable=SC2086
  set -- $shape
  std "$1" "$2" "$3" > "$tmp/std.exp"
  s=1
  while [ "$s" -le "$N" ]; do
    for v in orig new; do
      d=$tmp/km2022.$v
      mkdir -p "$d" && (cd "$d" && find . -type f -delete)
      prog=$tmp/km2022/flip
      [ "$v" = new ] && prog=$bin/km2022_flip
      (cd "$d" && KM_SEED=$s "$prog" "$tmp/std.exp" "$1" "$2" "$3" 20000 1 2> /dev/null | cut -d, -f2 > out.txt; cut -d, -f5,6 j00.log >> out.txt)
    done
    total=$((total + 1))
    cmp -s "$tmp/km2022.orig/out.txt" "$tmp/km2022.new/out.txt" && same=$((same + 1))
    s=$((s + 1))
  done
done
report km2022 "$same" "$total"

# tfg
same=0 total=0
for shape in "3 3 3" "3 3 4"; do
  # shellcheck disable=SC2086
  set -- $shape
  s=1
  while [ "$s" -le "$N" ]; do
    for v in orig new; do
      d=$tmp/tfg.$v
      mkdir -p "$d" && (cd "$d" && find . -type f -delete)
      prog=$tmp/tfg/flip_graph
      [ "$v" = new ] && prog=$bin/tfg_flip_graph
      (cd "$d" && $limit "$prog" -n1 "$1" -n2 "$2" -n3 "$3" --ring Z2 --count 4 --threads 1 --seed "$s" --flip-iterations 100000 -o "$d/out" 2> /dev/null \
        | grep -E '^\|  +[0-9]+ \|' | head -40 > rows.txt || true)
    done
    total=$((total + 1))
    if [ "$(wc -l < "$tmp/tfg.orig/rows.txt")" -eq 40 ] && cmp -s "$tmp/tfg.orig/rows.txt" "$tmp/tfg.new/rows.txt"; then same=$((same + 1)); fi
    s=$((s + 1))
  done
done
report tfg "$same" "$total"
