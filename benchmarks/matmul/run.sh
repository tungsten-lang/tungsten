#!/bin/bash
# Build and run the matmul benchmarks at Tungsten's --release flags.
#   benchmarks/matmul/run.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Tungsten --release backend flags (compiler/tungsten.w).
CFLAGS="-O3 -DNDEBUG -march=native -mtune=native -flto"

echo "== C: fixed 3x3 / 4x4 schoolbook (ideal small) =="
clang $CFLAGS -o "$TMP/fixed_small" benchmarks/matmul/fixed_small.c -lm
"$TMP/fixed_small"
echo

echo "== C: NxN sweep — schoolbook vs Strassen vs Accelerate =="
clang $CFLAGS -Wno-deprecated-declarations -o "$TMP/sweep" benchmarks/matmul/sweep.c -framework Accelerate -lm
"$TMP/sweep"
echo

echo "== Tungsten: Mat3/Mat4 operator + NxN loop + dgemm =="
./bin/tungsten -o "$TMP/tm" --release --fast benchmarks/matmul/tungsten_matmul.w
"$TMP/tm"
