#!/usr/bin/env bash
# CUDA_ARCH=sm_100 (B200) or sm_121 (GB10), on an already-running CUDA host.
set -euo pipefail
cd "$(dirname "$0")/../../.."
command -v nvcc >/dev/null || { echo 'nvcc is required on a CUDA host' >&2; exit 1; }
cuda_arch=${CUDA_ARCH:-sm_100}
[[ "$cuda_arch" =~ ^sm_[0-9]+[af]?$ ]] || { echo 'Invalid CUDA_ARCH' >&2; exit 1; }
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cuda-router.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
for math_mode in precise fast; do
  flags=()
  if [[ "$math_mode" == fast ]]; then flags+=(--use_fast_math); fi
  nvcc -std=c++17 -O2 -arch="$cuda_arch" "${flags[@]}" \
    bits/tungsten-llama/scripts/test_upstream_router.cu -o "$build_dir/router-$math_mode"
  echo "CUDA math mode: $math_mode" >&2
  "$build_dir/router-$math_mode"
done
