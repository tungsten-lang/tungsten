#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
TMP_ROOT=${TMPDIR:-/tmp}
WORK="$TMP_ROOT/tungsten-big-math-language-compare-$$"
RESULTS="$WORK/results.csv"
CC=${CC:-clang}
FC=${FC:-gfortran}
GO=${GO:-go}
RUBY=${RUBY:-ruby}
PYTHON=${PYTHON:-python3}
NODE=${NODE:-node}
CARGO=${CARGO:-cargo}
RUST_TARGET_DIR="$WORK/rust-target"

rm -rf "$WORK"
mkdir -p "$WORK/rust/src"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
: > "$RESULTS"

SIZES=${SIZES:-"4096 16384 65536"}

CFLAGS="-O3 -mcpu=native -Wno-deprecated-declarations"
ONIG_CFLAGS=$(pkg-config --cflags oniguruma 2>/dev/null || true)
ONIG_LDFLAGS=$(pkg-config --libs oniguruma 2>/dev/null || true)

UNAME_S=$(uname -s)
case "$UNAME_S" in
  Darwin)
    EVENT_SRC="$RUNTIME/event_kqueue.c"
    METAL_SRC="$RUNTIME/metal.m $RUNTIME/graphics.m $RUNTIME/hid_bridge.m"
    PLATFORM_LDFLAGS="-framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework IOKit -framework CoreFoundation -framework Accelerate"
    ;;
  Linux)
    EVENT_SRC="$RUNTIME/event_epoll.c"
    METAL_SRC=
    PLATFORM_LDFLAGS=
    ;;
  *)
    echo "Unsupported platform: $UNAME_S" >&2
    exit 1
    ;;
esac

iters_for_bits() {
  case "$1" in
    4096) echo "${ITERS_4096:-5000}" ;;
    16384) echo "${ITERS_16384:-1000}" ;;
    65536) echo "${ITERS_65536:-120}" ;;
    *) echo "${ITERS_DEFAULT:-200}" ;;
  esac
}

print_results() {
  if [ "${FORMAT:-table}" = "csv" ]; then
    echo "language,bits,ns_per_mul,sink"
    cat "$RESULTS"
    return
  fi

  printf "%-20s %8s %14s %s\n" "language" "bits" "ns/mul" "sink"
  printf "%-20s %8s %14s %s\n" "--------------------" "--------" "--------------" "----------------"
  awk -F, 'NF == 4 { printf "%-20s %8s %14s %s\n", $1, $2, $3, $4 }' "$RESULTS"
}

cat > "$WORK/c_gmp.c" <<'C'
#include <gmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static uint64_t rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static void make_big(mpz_t z, int bits, uint64_t seed) {
    int limbs = (bits + 63) / 64;
    uint64_t *v = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    uint64_t state = seed;
    for (int i = 0; i < limbs; i++) v[i] = rng(&state);
    int top = bits & 63;
    if (top == 0) top = 64;
    if (top < 64) v[limbs - 1] &= ((1ULL << top) - 1ULL);
    v[limbs - 1] |= 1ULL << (top - 1);
    v[0] |= 1ULL;
    mpz_import(z, (size_t)limbs, -1, sizeof(uint64_t), 0, 0, v);
    free(v);
}

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int bits = argc > 1 ? atoi(argv[1]) : 4096;
    int iters = argc > 2 ? atoi(argv[2]) : 1000;
    mpz_t a, b, r;
    mpz_inits(a, b, r, NULL);
    make_big(a, bits, 0x123456789abcdef0ULL ^ (uint64_t)bits);
    make_big(b, bits, 0xfedcba9876543210ULL ^ (uint64_t)bits);
    volatile uint64_t sink = 0;
    mpz_mul(r, a, b);
    double start = now_sec();
    for (int i = 0; i < iters; i++) {
        mpz_mul(r, a, b);
        sink ^= (uint64_t)mpz_getlimbn(r, 0) + (uint64_t)i;
    }
    double ns = (now_sec() - start) * 1e9 / (double)iters;
    printf("c-gmp,%d,%.1f,%llu\n", bits, ns, (unsigned long long)sink);
    mpz_clears(a, b, r, NULL);
    return 0;
}
C

cat > "$WORK/tungsten_runtime.c" <<'C'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "runtime.c"

static volatile uint64_t tungsten_lang_sink;

static uint64_t tungsten_lang_rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

static void tungsten_lang_make_limbs(uint64_t *limbs, int bits, uint64_t seed) {
    int n = (bits + 63) / 64;
    uint64_t state = seed;
    for (int i = 0; i < n; i++) limbs[i] = tungsten_lang_rng(&state);

    int top = bits & 63;
    if (top == 0) top = 64;
    if (top < 64) limbs[n - 1] &= ((1ULL << top) - 1ULL);
    limbs[n - 1] |= 1ULL << (top - 1);
    limbs[0] |= 1ULL;
}

static double tungsten_lang_now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int bits = argc > 1 ? atoi(argv[1]) : 4096;
    int iters = argc > 2 ? atoi(argv[2]) : 1000;
    int limbs = (bits + 63) / 64;
    uint64_t *a = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    uint64_t *b = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    uint64_t *out = (uint64_t *)calloc((size_t)limbs * 2U + 4U, sizeof(uint64_t));
    if (!a || !b || !out) {
        fprintf(stderr, "out of memory in tungsten runtime benchmark\n");
        return 1;
    }

    tungsten_lang_make_limbs(a, bits, 0x123456789abcdef0ULL ^ (uint64_t)bits);
    tungsten_lang_make_limbs(b, bits, 0xfedcba9876543210ULL ^ (uint64_t)bits);
    bigint_mul_dispatch(out, a, limbs, b, limbs);
    double start = tungsten_lang_now_sec();
    for (int i = 0; i < iters; i++) {
        bigint_mul_dispatch(out, a, limbs, b, limbs);
        tungsten_lang_sink ^= out[0] + (uint64_t)i;
    }
    double ns = (tungsten_lang_now_sec() - start) * 1e9 / (double)iters;
    printf("tungsten-runtime,%d,%.1f,%llu\n", bits, ns, (unsigned long long)tungsten_lang_sink);

    free(out);
    free(b);
    free(a);
    return 0;
}
C

cat > "$WORK/go_big.go" <<'GO'
package main

import (
	"fmt"
	"math/big"
	"os"
	"strconv"
	"time"
)

func rng(state *uint64) uint64 {
	x := *state
	x ^= x >> 12
	x ^= x << 25
	x ^= x >> 27
	*state = x
	return x * 2685821657736338717
}

func makeBig(bits int, seed uint64) *big.Int {
	limbs := (bits + 63) / 64
	words := make([]big.Word, limbs)
	state := seed
	for i := 0; i < limbs; i++ {
		words[i] = big.Word(rng(&state))
	}
	top := bits & 63
	if top == 0 {
		top = 64
	}
	if top < 64 {
		words[limbs-1] &= big.Word((uint64(1) << uint(top)) - 1)
	}
	words[limbs-1] |= big.Word(uint64(1) << uint(top-1))
	words[0] |= 1
	return new(big.Int).SetBits(words)
}

func main() {
	bits := 4096
	iters := 1000
	if len(os.Args) > 1 {
		bits, _ = strconv.Atoi(os.Args[1])
	}
	if len(os.Args) > 2 {
		iters, _ = strconv.Atoi(os.Args[2])
	}
	a := makeBig(bits, 0x123456789abcdef0^uint64(bits))
	b := makeBig(bits, 0xfedcba9876543210^uint64(bits))
	r := new(big.Int)
	var sink uint64
	r.Mul(a, b)
	start := time.Now()
	for i := 0; i < iters; i++ {
		r.Mul(a, b)
		sink ^= uint64(r.Bits()[0]) + uint64(i)
	}
	ns := float64(time.Since(start).Nanoseconds()) / float64(iters)
	fmt.Printf("go-math-big,%d,%.1f,%d\n", bits, ns, sink)
}
GO

cat > "$WORK/fortran_gmp_helpers.c" <<'C'
#include <gmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

static uint64_t rng(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 2685821657736338717ULL;
}

void tw_fortran_make_big(mpz_t z, int bits, uint64_t seed) {
    int limbs = (bits + 63) / 64;
    uint64_t *v = (uint64_t *)calloc((size_t)limbs, sizeof(uint64_t));
    uint64_t state = seed;
    for (int i = 0; i < limbs; i++) v[i] = rng(&state);
    int top = bits & 63;
    if (top == 0) top = 64;
    if (top < 64) v[limbs - 1] &= ((1ULL << top) - 1ULL);
    v[limbs - 1] |= 1ULL << (top - 1);
    v[0] |= 1ULL;
    mpz_import(z, (size_t)limbs, -1, sizeof(uint64_t), 0, 0, v);
    free(v);
}

double tw_fortran_now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}
C

cat > "$WORK/fortran_gmp.f90" <<'F90'
program fortran_gmp_bench
  use iso_c_binding
  implicit none

  type, bind(C) :: mpz_struct
    integer(c_int) :: alloc
    integer(c_int) :: size
    type(c_ptr) :: d
  end type mpz_struct

  interface
    subroutine gmpz_init(x) bind(C, name="__gmpz_init")
      import :: mpz_struct
      type(mpz_struct), intent(inout) :: x
    end subroutine

    subroutine gmpz_clear(x) bind(C, name="__gmpz_clear")
      import :: mpz_struct
      type(mpz_struct), intent(inout) :: x
    end subroutine

    subroutine gmpz_mul(rop, op1, op2) bind(C, name="__gmpz_mul")
      import :: mpz_struct
      type(mpz_struct), intent(inout) :: rop
      type(mpz_struct), intent(in) :: op1
      type(mpz_struct), intent(in) :: op2
    end subroutine

    function gmpz_getlimbn(op, n) result(r) bind(C, name="__gmpz_getlimbn")
      import :: c_int64_t, c_size_t, mpz_struct
      type(mpz_struct), intent(in) :: op
      integer(c_size_t), value :: n
      integer(c_int64_t) :: r
    end function

    subroutine make_big(z, bits, seed) bind(C, name="tw_fortran_make_big")
      import :: c_int, c_int64_t, mpz_struct
      type(mpz_struct), intent(inout) :: z
      integer(c_int), value :: bits
      integer(c_int64_t), value :: seed
    end subroutine

    function now_sec() result(r) bind(C, name="tw_fortran_now_sec")
      import :: c_double
      real(c_double) :: r
    end function
  end interface

  integer(c_int) :: bits
  integer :: iters, i
  character(len=64) :: arg
  type(mpz_struct) :: a, b, r
  integer(c_int64_t) :: sink
  real(c_double) :: start, ns
  integer(c_int64_t), parameter :: seed_a = int(Z'123456789ABCDEF0', c_int64_t)
  integer(c_int64_t), parameter :: seed_b = int(Z'FEDCBA9876543210', c_int64_t)

  bits = 4096_c_int
  iters = 1000
  if (command_argument_count() >= 1) then
    call get_command_argument(1, arg)
    read(arg, *) bits
  end if
  if (command_argument_count() >= 2) then
    call get_command_argument(2, arg)
    read(arg, *) iters
  end if

  call gmpz_init(a)
  call gmpz_init(b)
  call gmpz_init(r)
  call make_big(a, bits, ieor(seed_a, int(bits, c_int64_t)))
  call make_big(b, bits, ieor(seed_b, int(bits, c_int64_t)))

  sink = 0_c_int64_t
  call gmpz_mul(r, a, b)
  start = now_sec()
  do i = 0, iters - 1
    call gmpz_mul(r, a, b)
    sink = ieor(sink, gmpz_getlimbn(r, 0_c_size_t) + int(i, c_int64_t))
  end do
  ns = (now_sec() - start) * 1000000000.0_c_double / real(iters, c_double)

  write(*, '(A,I0,A,F0.1,A,I0)') "fortran-gmp,", bits, ",", ns, ",", sink

  call gmpz_clear(a)
  call gmpz_clear(b)
  call gmpz_clear(r)
end program fortran_gmp_bench
F90

cat > "$WORK/ruby_big.rb" <<'RUBY'
def rng(state)
  x = state & 0xffffffffffffffff
  x ^= x >> 12
  x ^= (x << 25) & 0xffffffffffffffff
  x ^= x >> 27
  x &= 0xffffffffffffffff
  [x, (x * 2685821657736338717) & 0xffffffffffffffff]
end

def make_big(bits, seed)
  limbs = (bits + 63) / 64
  state = seed
  n = 0
  limbs.times do |i|
    state, word = rng(state)
    n |= word << (64 * i)
  end
  top = bits & 63
  top = 64 if top == 0
  if top < 64
    mask = (1 << (64 * (limbs - 1))) - 1
    n &= mask | (((1 << top) - 1) << (64 * (limbs - 1)))
  end
  n | (1 << (bits - 1)) | 1
end

bits = (ARGV[0] || "4096").to_i
iters = (ARGV[1] || "1000").to_i
a = make_big(bits, 0x123456789abcdef0 ^ bits)
b = make_big(bits, 0xfedcba9876543210 ^ bits)
sink = 0
r = a * b
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iters.times do |i|
  r = a * b
  sink ^= (r & 0xffffffffffffffff) + i
end
ns = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1_000_000_000.0 / iters
puts "ruby-integer,#{bits},#{format('%.1f', ns)},#{sink & 0xffffffffffffffff}"
RUBY

cat > "$WORK/python_big.py" <<'PY'
import sys
import time

MASK = (1 << 64) - 1

def rng(state):
    x = state & MASK
    x ^= x >> 12
    x ^= (x << 25) & MASK
    x ^= x >> 27
    x &= MASK
    return x, (x * 2685821657736338717) & MASK

def make_big(bits, seed):
    limbs = (bits + 63) // 64
    state = seed
    n = 0
    for i in range(limbs):
        state, word = rng(state)
        n |= word << (64 * i)
    top = bits & 63
    if top == 0:
        top = 64
    if top < 64:
        mask = (1 << (64 * (limbs - 1))) - 1
        n &= mask | (((1 << top) - 1) << (64 * (limbs - 1)))
    return n | (1 << (bits - 1)) | 1

bits = int(sys.argv[1]) if len(sys.argv) > 1 else 4096
iters = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
a = make_big(bits, 0x123456789abcdef0 ^ bits)
b = make_big(bits, 0xfedcba9876543210 ^ bits)
sink = 0
r = a * b
start = time.perf_counter_ns()
for i in range(iters):
    r = a * b
    sink ^= (r & MASK) + i
elapsed = time.perf_counter_ns() - start
print(f"python-int,{bits},{elapsed / iters:.1f},{sink & MASK}")
PY

cat > "$WORK/node_bigint.js" <<'JS'
const MASK = (1n << 64n) - 1n;

function rng(state) {
  let x = state & MASK;
  x ^= x >> 12n;
  x ^= (x << 25n) & MASK;
  x ^= x >> 27n;
  x &= MASK;
  return [x, (x * 2685821657736338717n) & MASK];
}

function makeBig(bits, seed) {
  const limbs = Math.floor((bits + 63) / 64);
  let state = BigInt(seed);
  let n = 0n;
  for (let i = 0; i < limbs; i++) {
    const pair = rng(state);
    state = pair[0];
    n |= pair[1] << BigInt(64 * i);
  }
  let top = bits & 63;
  if (top === 0) top = 64;
  if (top < 64) {
    const mask = (1n << BigInt(64 * (limbs - 1))) - 1n;
    n &= mask | (((1n << BigInt(top)) - 1n) << BigInt(64 * (limbs - 1)));
  }
  return n | (1n << BigInt(bits - 1)) | 1n;
}

const bits = Number(process.argv[2] || "4096");
const iters = Number(process.argv[3] || "1000");
const a = makeBig(bits, BigInt(0x123456789abcdef0n ^ BigInt(bits)));
const b = makeBig(bits, BigInt(0xfedcba9876543210n ^ BigInt(bits)));
let sink = 0n;
let r = a * b;
const start = process.hrtime.bigint();
for (let i = 0; i < iters; i++) {
  r = a * b;
  sink ^= (r & MASK) + BigInt(i);
}
const elapsed = Number(process.hrtime.bigint() - start);
console.log(`node-bigint,${bits},${(elapsed / iters).toFixed(1)},${sink & MASK}`);
JS

cat > "$WORK/rust/Cargo.toml" <<'TOML'
[package]
name = "tungsten-big-math-language-compare"
version = "0.1.0"
edition = "2024"

[dependencies]
num-bigint = "0.4"
num-traits = "0.2"
TOML

cat > "$WORK/rust/src/main.rs" <<'RS'
use num_bigint::BigUint;
use std::env;
use std::time::Instant;

fn rng(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(2685821657736338717)
}

fn make_big(bits: usize, seed: u64) -> BigUint {
    let limbs = (bits + 63) / 64;
    let mut bytes = vec![0u8; limbs * 8];
    let mut state = seed;
    for i in 0..limbs {
        let word = rng(&mut state);
        bytes[i * 8..i * 8 + 8].copy_from_slice(&word.to_le_bytes());
    }
    let top = match bits & 63 {
        0 => 64,
        n => n,
    };
    if top < 64 {
        let keep = ((1u64 << top) - 1).to_le_bytes();
        let off = (limbs - 1) * 8;
        let mut word = u64::from_le_bytes(bytes[off..off + 8].try_into().unwrap());
        word &= u64::from_le_bytes(keep);
        bytes[off..off + 8].copy_from_slice(&word.to_le_bytes());
    }
    let bit = bits - 1;
    bytes[bit / 8] |= 1u8 << (bit & 7);
    bytes[0] |= 1;
    BigUint::from_bytes_le(&bytes)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let bits = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(4096usize);
    let iters = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1000usize);
    let a = make_big(bits, 0x123456789abcdef0u64 ^ bits as u64);
    let b = make_big(bits, 0xfedcba9876543210u64 ^ bits as u64);
    let mut sink = 0u64;
    let _warm = &a * &b;
    let start = Instant::now();
    for i in 0..iters {
        let r = &a * &b;
        sink ^= r.iter_u64_digits().next().unwrap_or(0).wrapping_add(i as u64);
    }
    let ns = start.elapsed().as_secs_f64() * 1e9 / iters as f64;
    println!("rust-num-bigint,{},{:.1},{}", bits, ns, sink);
}
RS

if pkg-config --libs gmp >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  "$CC" $CFLAGS $(pkg-config --cflags gmp) "$WORK/c_gmp.c" $(pkg-config --libs gmp) -o "$WORK/c_gmp"
  for bits in $SIZES; do "$WORK/c_gmp" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
else
  echo "c-gmp,skipped,missing-gmp,0" >&2
fi

# shellcheck disable=SC2086
"$CC" $CFLAGS $ONIG_CFLAGS -I"$RUNTIME" \
  "$WORK/tungsten_runtime.c" \
  "$EVENT_SRC" "$RUNTIME/terminal_input.c" "$RUNTIME/tls_stub.c" "$RUNTIME/aks.c" $METAL_SRC \
  $ONIG_LDFLAGS $PLATFORM_LDFLAGS \
  -o "$WORK/tungsten_runtime"
for bits in $SIZES; do "$WORK/tungsten_runtime" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done

if command -v "$GO" >/dev/null 2>&1; then
  "$GO" build -o "$WORK/go_big" "$WORK/go_big.go"
  for bits in $SIZES; do "$WORK/go_big" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
fi

if command -v "$FC" >/dev/null 2>&1 && pkg-config --libs gmp >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  "$CC" $CFLAGS $(pkg-config --cflags gmp) -c "$WORK/fortran_gmp_helpers.c" -o "$WORK/fortran_gmp_helpers.o"
  # shellcheck disable=SC2086
  "$FC" $CFLAGS "$WORK/fortran_gmp.f90" "$WORK/fortran_gmp_helpers.o" $(pkg-config --libs gmp) -o "$WORK/fortran_gmp"
  for bits in $SIZES; do "$WORK/fortran_gmp" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
fi

if command -v "$RUBY" >/dev/null 2>&1; then
  for bits in $SIZES; do "$RUBY" "$WORK/ruby_big.rb" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
fi

if command -v "$PYTHON" >/dev/null 2>&1; then
  for bits in $SIZES; do "$PYTHON" "$WORK/python_big.py" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
fi

if command -v "$NODE" >/dev/null 2>&1; then
  for bits in $SIZES; do "$NODE" "$WORK/node_bigint.js" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
fi

if command -v "$CARGO" >/dev/null 2>&1; then
  if [ "${VERBOSE:-0}" = "1" ]; then
    if CARGO_TARGET_DIR="$RUST_TARGET_DIR" "$CARGO" build --manifest-path "$WORK/rust/Cargo.toml" --release; then
      cargo_status=0
    else
      cargo_status=$?
    fi
  else
    if CARGO_TARGET_DIR="$RUST_TARGET_DIR" "$CARGO" build --manifest-path "$WORK/rust/Cargo.toml" --release >/dev/null 2>&1; then
      cargo_status=0
    else
      cargo_status=$?
    fi
  fi
  if [ "$cargo_status" -eq 0 ]; then
    for bits in $SIZES; do "$RUST_TARGET_DIR/release/tungsten-big-math-language-compare" "$bits" "$(iters_for_bits "$bits")" >> "$RESULTS"; done
  else
    echo "rust-num-bigint,skipped,cargo-build-failed,0" >&2
  fi
fi

print_results
