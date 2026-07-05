#!/bin/bash
# run.sh — Run all WValue type benchmarks across languages
# Usage: ./run.sh [benchmark_name]   (e.g., ./run.sh int_collatz)
#        ./run.sh                     (runs all benchmarks)

set -e
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
BUILD=build
mkdir -p "$BUILD"

# Tungsten compilation: generate IR via interpreted pipeline, then clang
RUNTIME_DIR="$ROOT/runtime"
TLS_ENABLED="${TLS:-${TUNGSTEN_TLS:-}}"
OPENSSL_PREFIX=""
TLS_FLAGS=""
TLS_SRCS=("$RUNTIME_DIR/tls_stub.c")
if [ -n "$TLS_ENABLED" ]; then
  OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || true)"
  if [ -n "$OPENSSL_PREFIX" ]; then
    TLS_FLAGS="-DTUNGSTEN_TLS -I$OPENSSL_PREFIX/include -L$OPENSSL_PREFIX/lib -lssl -lcrypto"
    TLS_SRCS+=("$RUNTIME_DIR/tls.c")
  fi
fi

if [ "$(uname -s)" = "Darwin" ]; then
  EVENT_SRC="$RUNTIME_DIR/event_kqueue.c"
elif [ "$(uname -s)" = "Linux" ] && [ -n "${USE_IOURING:-}" ]; then
  EVENT_SRC="$RUNTIME_DIR/event_iouring.c"
elif [ "$(uname -s)" = "Linux" ]; then
  EVENT_SRC="$RUNTIME_DIR/event_epoll.c"
else
  EVENT_SRC="$RUNTIME_DIR"/event_*.c
fi

compile_tungsten() {
  local src="$1" bin="$2"
  local ll="${bin}.ll"
  ruby "$ROOT/bin/tungsten.rb" --fast --ll "$src" > "$ll" 2>/dev/null || return 1
  # -ffast-math is the `--fast` equivalent for this hand-rolled harness (it
  # invokes clang directly instead of `bin/tungsten --fast`): enables LLVM's
  # auto-vectorizer on the emitted scalar float loops.
  clang -O3 -DNDEBUG -ffast-math -march=native -mtune=native -flto -Wno-override-module \
    -Wl,-dead_strip -Wl,-stack_size,0x4000000 \
    $TLS_FLAGS \
    "$RUNTIME_DIR/runtime.c" "$EVENT_SRC" "${TLS_SRCS[@]}" \
    "$RUNTIME_DIR/aks.c" \
    "$ll" -o "$bin" 2>/dev/null || return 1
  rm -f "$ll"
  return 0
}

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[91m'
RESET='\033[0m'

BENCHMARKS=(
  int_collatz
  float_mandelbrot
  bool_sieve
  string_count
  array_sort
  hash_freq
  struct_nbody
  closure_iter
  decimal_e
  complex_julia
  rational_harmonic
  bigint_fib
)

if [ -n "$1" ]; then
  BENCHMARKS=("$1")
fi

run_one() {
  local name="$1" lang="$2" cmd="$3"
  local output
  output=$(eval "$cmd" 2>&1) || true
  local result=$(echo "$output" | head -1)
  local elapsed=$(echo "$output" | grep -o 'elapsed: [0-9.]*s' | head -1)
  if [ -z "$elapsed" ]; then
    elapsed="error"
  fi
  printf "  %-10s %-14s %s\n" "$lang" "$elapsed" "$result"
}

for bench in "${BENCHMARKS[@]}"; do
  echo -e "\n${BOLD}${CYAN}━━━ $bench ━━━${RESET}"

  # C
  if [ -f "${bench}.c" ]; then
    GMP_FLAG=""
    if grep -q "gmp.h" "${bench}.c" 2>/dev/null; then
      GMP_FLAG="-lgmp"
    fi
    if clang -O2 -lm $GMP_FLAG "${bench}.c" -o "$BUILD/${bench}_c" 2>/dev/null; then
      run_one "$bench" "C" "./$BUILD/${bench}_c"
    else
      printf "  %-10s %-14s %s\n" "C" "compile err" ""
    fi
  fi

  # Go
  if [ -f "${bench}.go" ]; then
    run_one "$bench" "Go" "go run ${bench}.go"
  fi

  # Rust
  if [ -f "${bench}.rs" ]; then
    if rustc -O -o "$BUILD/${bench}_rs" "${bench}.rs" 2>/dev/null; then
      run_one "$bench" "Rust" "./$BUILD/${bench}_rs"
    else
      printf "  %-10s %-14s %s\n" "Rust" "compile err" ""
    fi
  fi

  # Ruby
  if [ -f "${bench}.rb" ]; then
    run_one "$bench" "Ruby" "ruby ${bench}.rb"
  fi

  # Crystal
  if [ -f "${bench}.cr" ]; then
    if crystal build --release -o "$BUILD/${bench}_cr" "${bench}.cr" 2>/dev/null; then
      run_one "$bench" "Crystal" "./$BUILD/${bench}_cr"
    else
      printf "  %-10s %-14s %s\n" "Crystal" "compile err" ""
    fi
  fi

  # Python
  if [ -f "${bench}.py" ]; then
    run_one "$bench" "Python" "python3 ${bench}.py"
  fi

  # Tungsten (compiled)
  if [ -f "${bench}.w" ]; then
    if compile_tungsten "${bench}.w" "$BUILD/${bench}_w" 2>/dev/null; then
      run_one "$bench" "Tungsten" "./$BUILD/${bench}_w"
    else
      printf "  %-10s %-14s %s\n" "Tungsten" "compile err" ""
    fi
  fi
done

echo ""
