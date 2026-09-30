#!/bin/sh
# Build the baseline programs of the metabench comparison, out of tree.
#
#   SOTA_SRC     directory that holds the pinned clones  flips/ (Kauers-Moosbauer)  and  tfg/ (Perminov)
#                default: ~/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota
#   SOTA_BUILD   output directory (src/, bin/, BUILD-INFO.txt)          default: $SOTA_SRC/build
#   CXX          C++ compiler                                            default: Homebrew LLVM clang++
#   OMP_PREFIX   prefix with lib/libomp.dylib and lib/clang/*/include/omp.h  default: the prefix of $CXX
#   CPU_FLAG     -mcpu value                                             default: apple-m5 (else native)
#   SOTA_ALLOW_UNPINNED=1   build a clone whose HEAD differs from the pin (the result is then not the pinned build)
#
# The third-party sources are not vendored: each program is copied from its clone, the instrumentation patch of
# adapters/patches/ is applied to the copy, and the copy is compiled. The clones stay untouched.
#
# Produces  $SOTA_BUILD/bin/{km2022_flip,km2024_flip,tfg_flip_graph}  and  $SOTA_BUILD/BUILD-INFO.txt.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
patches=$here/adapters/patches

SOTA_SRC=${SOTA_SRC:-$HOME/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota}
SOTA_BUILD=${SOTA_BUILD:-$SOTA_SRC/build}
CXX=${CXX:-/opt/homebrew/opt/llvm/bin/clang++}
OMP_PREFIX=${OMP_PREFIX:-$(cd "$(dirname "$CXX")/.." && pwd)}
JOBS=${JOBS:-4}

KM_PIN=e31a0a0f0d2577cee5da047ca7dcae0c61992e40
TFG_PIN=b942f005c61882f678fafb65ba4f9f348f9ef8df

die() { echo "build.sh: $*" >&2; exit 1; }

[ -x "$CXX" ] || die "compiler $CXX not found"
[ -d "$SOTA_SRC/flips" ] && [ -d "$SOTA_SRC/tfg" ] || die "clones flips/ and tfg/ not found under $SOTA_SRC"

# The most specific -mcpu the compiler accepts: apple-m5, else native.
CPU_FLAG=${CPU_FLAG:-apple-m5}
if ! "$CXX" -mcpu="$CPU_FLAG" -fsyntax-only -x c++ /dev/null > /dev/null 2>&1; then
  CPU_FLAG=native
  "$CXX" -mcpu=native -fsyntax-only -x c++ /dev/null > /dev/null 2>&1 || die "$CXX accepts neither -mcpu=apple-m5 nor -mcpu=native"
fi
CXXFLAGS="-O3 -flto -mcpu=$CPU_FLAG -std=c++17 -DNDEBUG"

export GIT_NO_LAZY_FETCH=1

check_pin() { # dir pin
  head=$(git -C "$1" rev-parse HEAD)
  if [ "$head" != "$2" ] && [ "${SOTA_ALLOW_UNPINNED:-0}" != 1 ]; then
    die "$1 is at $head, the pin is $2 (set SOTA_ALLOW_UNPINNED=1 to build anyway)"
  fi
  [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ] || die "$1 has local modifications"
}
check_pin "$SOTA_SRC/flips" "$KM_PIN"
check_pin "$SOTA_SRC/tfg" "$TFG_PIN"

mkdir -p "$SOTA_BUILD/src" "$SOTA_BUILD/bin"

fresh_copy() { # source-dir target-dir : a clean copy without .git and build products
  dest=$2
  [ -n "$dest" ] && [ -d "$SOTA_BUILD" ] || die "bad target"
  if [ -d "$dest" ]; then
    find "$dest" -depth -delete
  fi
  mkdir -p "$dest"
  (cd "$1" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -)
}

# 1. Kauers-Moosbauer, code/ (Flip graphs for matrix multiplication, 2022)
fresh_copy "$SOTA_SRC/flips/code" "$SOTA_BUILD/src/km2022"
(cd "$SOTA_BUILD/src/km2022" && patch -p1 -s < "$patches/km2022-instrumentation.patch")
# -DEXPECT is the program's own switch for branch hints (scheme.hpp); it does not change the search
(cd "$SOTA_BUILD/src/km2022" && "$CXX" $CXXFLAGS -DEXPECT -o "$SOTA_BUILD/bin/km2022_flip" scheme.cpp randompath.cpp main.cpp)

# 2. Kauers-Moosbauer, updated_code/ (plus transition of Arai et al., faster data structures)
fresh_copy "$SOTA_SRC/flips/updated_code" "$SOTA_BUILD/src/km2024"
(cd "$SOTA_BUILD/src/km2024" && patch -p1 -s < "$patches/km2024-instrumentation.patch")
(cd "$SOTA_BUILD/src/km2024" && "$CXX" $CXXFLAGS -o "$SOTA_BUILD/bin/km2024_flip" main_mm.cpp tensor.cpp mm.cpp pairSet.cpp)

# 3. Perminov ternary_flip_graph, flip_graph (OpenMP; run with one thread)
fresh_copy "$SOTA_SRC/tfg" "$SOTA_BUILD/src/tfg"
(cd "$SOTA_BUILD/src/tfg" && patch -p1 -s < "$patches/tfg-instrumentation.patch")
OMP_INC=$(ls -d "$OMP_PREFIX"/lib/clang/*/include 2> /dev/null | head -1)
TFG_FLAGS="$CXXFLAGS -Wno-unused-command-line-argument -fopenmp -I$OMP_INC"
(cd "$SOTA_BUILD/src/tfg" && make -s -j"$JOBS" flip_graph CXX="$CXX" FLAGS="$TFG_FLAGS -L$OMP_PREFIX/lib -Wl,-rpath,$OMP_PREFIX/lib")
cp "$SOTA_BUILD/src/tfg/flip_graph" "$SOTA_BUILD/bin/tfg_flip_graph"

# Build record
{
  echo "built:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host:       $(uname -srm), $(sysctl -n machdep.cpu.brand_string 2> /dev/null || true)"
  echo "compiler:   $("$CXX" --version | head -1)  ($CXX)"
  echo "flags:      $CXXFLAGS   (km2022 adds: -DEXPECT; tfg adds: -fopenmp -I$OMP_INC -L$OMP_PREFIX/lib -Wl,-rpath,$OMP_PREFIX/lib)"
  echo "libomp:     $OMP_PREFIX/lib/libomp.dylib"
  echo "flips:      $(git -C "$SOTA_SRC/flips" rev-parse HEAD)   (code/ -> km2022, updated_code/ -> km2024)"
  echo "tfg:        $(git -C "$SOTA_SRC/tfg" rev-parse HEAD)"
  for f in km2022_flip km2024_flip tfg_flip_graph; do
    echo "sha256:     $(shasum -a 256 "$SOTA_BUILD/bin/$f" | cut -d' ' -f1)  bin/$f"
  done
  for f in km2022 km2024 tfg; do
    echo "patch:      $(shasum -a 256 "$patches/$f-instrumentation.patch" | cut -d' ' -f1)  adapters/patches/$f-instrumentation.patch"
  done
} > "$SOTA_BUILD/BUILD-INFO.txt"
cat "$SOTA_BUILD/BUILD-INFO.txt"
