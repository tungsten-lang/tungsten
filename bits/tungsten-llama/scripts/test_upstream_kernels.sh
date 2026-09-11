#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/tungsten-upstream-kernels.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
xcrun clang++ -std=c++17 -O2 -fobjc-arc -framework Foundation -framework Metal \
  bits/tungsten-llama/scripts/test_upstream_kernels.mm -o "$build_dir/test-kernels"
"$build_dir/test-kernels"
