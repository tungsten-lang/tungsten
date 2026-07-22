#!/bin/sh
# Static/non-cloud regression for the Runpod setup contract.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SETUP="$SELF_DIR/setup_runpod.sh"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-runpod-plan.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

sh -n "$SETUP"

printf '%s\n' \
  'ID=ubuntu' \
  'VERSION_ID="22.04"' \
  'VERSION_CODENAME=jammy' > "$TEST_DIR/os-release"

METAFLIP_OS_RELEASE="$TEST_DIR/os-release" \
  METAFLIP_LLVM_MAJOR=18 \
  "$SETUP" --dry-run > "$TEST_DIR/plan"

expect_plan() {
  needle=$1
  if ! grep -Fq "$needle" "$TEST_DIR/plan"; then
    echo "CUDA777_SETUP_TEST missing plan entry: $needle" >&2
    exit 1
  fi
}

expect_plan 'libopenblas-dev'
expect_plan 'ruby'
expect_plan 'https://apt.llvm.org/jammy/'
expect_plan 'llvm-toolchain-jammy-18'
expect_plan 'clang-18 llvm-18 lld-18'
expect_plan 'ln -sfn /usr/bin/clang-18 /usr/local/bin/clang'
expect_plan 'WRITE_NVCC_WRAPPER /usr/local/bin/nvcc -> /usr/local/cuda/bin/nvcc'
expect_plan 'CHECK setup_runpod.sh --check'

# Exercise the functional check without a GPU or Linux package mutation. The
# fake compiler accepts every link probe and records each requested output;
# the setup script still owns version/path validation and probe sequencing.
mkdir -p "$TEST_DIR/fake-bin"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "${1:-}" = --version ]; then' \
  '  printf "clang version %s.0.0\\n" "${FAKE_CLANG_MAJOR:-18}"' \
  '  exit 0' \
  'fi' \
  'out=' \
  'while [ "$#" -gt 0 ]; do' \
  '  if [ "$1" = -o ] && [ "$#" -ge 2 ]; then shift; out=$1; fi' \
  '  shift' \
  'done' \
  'if [ -n "$out" ]; then : > "$out"; chmod +x "$out"; fi' \
  'exit 0' > "$TEST_DIR/fake-bin/clang"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\\n" "Cuda compilation tools, release 12.8, V12.8.0"' \
  'exit 0' > "$TEST_DIR/fake-bin/nvcc"
chmod +x "$TEST_DIR/fake-bin/clang" "$TEST_DIR/fake-bin/nvcc"

PATH="$TEST_DIR/fake-bin:$PATH" NVCC="$TEST_DIR/fake-bin/nvcc" \
  "$SETUP" --check > "$TEST_DIR/check.out"
if ! grep -Fq 'CUDA777_RUNPOD_SETUP_OK' "$TEST_DIR/check.out"; then
  echo "CUDA777_SETUP_TEST functional check did not accept the complete toolchain" >&2
  exit 1
fi

if PATH="$TEST_DIR/fake-bin:$PATH" NVCC="$TEST_DIR/fake-bin/nvcc" \
    FAKE_CLANG_MAJOR=15 "$SETUP" --check \
    > "$TEST_DIR/check-old.out" 2> "$TEST_DIR/check-old.err"; then
  echo "CUDA777_SETUP_TEST functional check accepted clang 15" >&2
  exit 1
fi
if ! grep -Fq 'clang 15 is too old' "$TEST_DIR/check-old.err"; then
  echo "CUDA777_SETUP_TEST functional clang rejection had the wrong diagnostic" >&2
  exit 1
fi

if METAFLIP_OS_RELEASE="$TEST_DIR/os-release" METAFLIP_LLVM_MAJOR=15 \
    "$SETUP" --dry-run > "$TEST_DIR/old.out" 2> "$TEST_DIR/old.err"; then
  echo "CUDA777_SETUP_TEST accepted clang 15" >&2
  exit 1
fi
if ! grep -Fq 'requires clang 18 or newer' "$TEST_DIR/old.err"; then
  echo "CUDA777_SETUP_TEST clang 15 rejection had the wrong diagnostic" >&2
  exit 1
fi

printf '%s\n' 'ID=debian' 'VERSION_CODENAME=bookworm' > "$TEST_DIR/debian-release"
if METAFLIP_OS_RELEASE="$TEST_DIR/debian-release" \
    "$SETUP" --dry-run > "$TEST_DIR/os.out" 2> "$TEST_DIR/os.err"; then
  echo "CUDA777_SETUP_TEST accepted an untested base distribution" >&2
  exit 1
fi
if ! grep -Fq 'supported images are Ubuntu 22.04 (jammy) and 24.04 (noble)' \
    "$TEST_DIR/os.err"; then
  echo "CUDA777_SETUP_TEST unsupported distribution had the wrong diagnostic" >&2
  exit 1
fi

printf '%s\n' 'CUDA777_SETUP_TEST ok llvm=18 distro=jammy ruby=present openblas=present nvcc=exposed'
