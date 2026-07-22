#!/bin/sh
# Prepare an official Ubuntu Runpod image for the Metaflip CUDA relay.
#
# The official Runpod PyTorch image is SSH-ready and already contains CUDA,
# but its Ubuntu 22.04 tag currently exposes clang 14 and keeps nvcc outside
# PATH. This Tungsten checkout emits LLVM IR that needs clang >= 18, and its
# native self-host link needs OpenBLAS plus Ruby. Keep those cloud
# assumptions in one checked, repeatable setup step.
set -eu

LLVM_MAJOR=${METAFLIP_LLVM_MAJOR:-18}
OS_RELEASE=${METAFLIP_OS_RELEASE:-/etc/os-release}
MODE=install

usage() {
  cat <<'EOF'
usage: setup_runpod.sh [--check | --dry-run]

  (no option)  install the pinned Ubuntu toolchain, expose nvcc, then check it
  --check      make no changes; functionally check the active toolchain
  --dry-run    print the Ubuntu install/link plan without making changes

Environment:
  METAFLIP_LLVM_MAJOR  LLVM major to install (default: 18; minimum: 18)
  METAFLIP_OS_RELEASE  alternate os-release file (primarily for plan testing)
  NVCC                 explicit nvcc path or command for install/check
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      MODE=check
      shift
      ;;
    --dry-run)
      MODE=dry-run
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "setup_runpod.sh: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$LLVM_MAJOR" in
  ''|*[!0-9]*)
    echo "setup_runpod.sh: METAFLIP_LLVM_MAJOR must be an integer" >&2
    exit 2
    ;;
esac
if [ "$LLVM_MAJOR" -lt 18 ]; then
  echo "setup_runpod.sh: this Tungsten checkout requires clang 18 or newer" >&2
  exit 2
fi

find_nvcc() {
  if [ -n "${NVCC:-}" ]; then
    command -v "$NVCC" 2>/dev/null || return 1
    return
  fi
  # Prefer the canonical toolkit driver over our PATH wrapper.  This keeps a
  # second setup run idempotent instead of resolving the wrapper to itself.
  if [ -x /usr/local/cuda/bin/nvcc ]; then
    printf '%s\n' /usr/local/cuda/bin/nvcc
    return
  fi
  command -v nvcc 2>/dev/null && return
  return 1
}

check_toolchain() {
  clang_path=$(command -v clang 2>/dev/null || true)
  if [ -z "$clang_path" ]; then
    echo "setup_runpod.sh: clang is not on PATH; run this script without --check" >&2
    return 1
  fi
  clang_major=$(
    "$clang_path" --version 2>/dev/null |
      sed -n '1s/.*clang version \([0-9][0-9]*\).*/\1/p'
  )
  case "$clang_major" in
    ''|*[!0-9]*)
      echo "setup_runpod.sh: could not parse clang version from $clang_path" >&2
      return 1
      ;;
  esac
  if [ "$clang_major" -lt 18 ]; then
    echo "setup_runpod.sh: clang $clang_major is too old; run this script without --check" >&2
    return 1
  fi

  nvcc_path=$(find_nvcc || true)
  if [ -z "$nvcc_path" ] || [ ! -x "$nvcc_path" ]; then
    echo "setup_runpod.sh: nvcc not found; use an official CUDA-devel Runpod template" >&2
    return 1
  fi
  if ! command -v ruby >/dev/null 2>&1; then
    echo "setup_runpod.sh: ruby is unavailable; the stage-two compiler build needs it" >&2
    return 1
  fi

  check_dir=$(mktemp -d "${TMPDIR:-/tmp}/metaflip-runpod-check.XXXXXX")
  trap 'rm -rf "$check_dir"' EXIT HUP INT TERM

  printf '%s\n' 'int main(void) { return 0; }' > "$check_dir/lld.c"
  if ! "$clang_path" -fuse-ld=lld "$check_dir/lld.c" -o "$check_dir/lld"; then
    echo "setup_runpod.sh: clang cannot link with lld" >&2
    return 1
  fi

  printf '%s\n' '#include <zstd.h>' 'int main(void) { return ZSTD_versionNumber() == 0; }' \
    > "$check_dir/zstd.c"
  if ! "$clang_path" "$check_dir/zstd.c" -lzstd -o "$check_dir/zstd"; then
    echo "setup_runpod.sh: libzstd headers/library are unavailable" >&2
    return 1
  fi

  printf '%s\n' '#include <oniguruma.h>' 'int main(void) { return ONIGURUMA_VERSION_MAJOR < 1; }' \
    > "$check_dir/onig.c"
  if ! "$clang_path" "$check_dir/onig.c" -lonig -o "$check_dir/onig"; then
    echo "setup_runpod.sh: Oniguruma headers/library are unavailable" >&2
    return 1
  fi

  printf '%s\n' '#include <cblas.h>' \
    'int main(void) { return cblas_sdot(0, 0, 1, 0, 1) != 0.0f; }' \
    > "$check_dir/openblas.c"
  if ! "$clang_path" "$check_dir/openblas.c" -lopenblas -o "$check_dir/openblas"; then
    echo "setup_runpod.sh: OpenBLAS headers/library are unavailable (install libopenblas-dev)" >&2
    return 1
  fi

  if ! "$nvcc_path" --version >/dev/null; then
    echo "setup_runpod.sh: nvcc exists but cannot run: $nvcc_path" >&2
    return 1
  fi

  printf 'CUDA777_RUNPOD_SETUP_OK clang=%s clang_major=%s nvcc=%s\n' \
    "$clang_path" "$clang_major" "$nvcc_path"
  rm -rf "$check_dir"
  trap - EXIT HUP INT TERM
}

if [ "$MODE" = check ]; then
  check_toolchain
  exit
fi

if [ ! -r "$OS_RELEASE" ]; then
  echo "setup_runpod.sh: cannot read $OS_RELEASE" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$OS_RELEASE"
case "${ID:-}:${VERSION_CODENAME:-}" in
  ubuntu:jammy|ubuntu:noble) ;;
  *)
    echo "setup_runpod.sh: supported images are Ubuntu 22.04 (jammy) and 24.04 (noble)" >&2
    exit 1
    ;;
esac

LLVM_REPO="https://apt.llvm.org/$VERSION_CODENAME/"
LLVM_SUITE="llvm-toolchain-$VERSION_CODENAME-$LLVM_MAJOR"
LLVM_KEY_URL=https://apt.llvm.org/llvm-snapshot.gpg.key
LLVM_KEY=/usr/share/keyrings/apt.llvm.org.asc
LLVM_LIST=/etc/apt/sources.list.d/metaflip-llvm.list
BASE_PACKAGES="ca-certificates curl git build-essential make pkg-config libonig-dev libzstd-dev libopenblas-dev rsync ruby"
LLVM_PACKAGES="clang-$LLVM_MAJOR llvm-$LLVM_MAJOR lld-$LLVM_MAJOR"

run_cmd() {
  if [ "$MODE" = dry-run ]; then
    printf 'RUN'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

write_llvm_source() {
  source_line="deb [signed-by=$LLVM_KEY] $LLVM_REPO $LLVM_SUITE main"
  if [ "$MODE" = dry-run ]; then
    printf 'WRITE %s %s\n' "$LLVM_LIST" "$source_line"
  else
    printf '%s\n' "$source_line" > "$LLVM_LIST"
  fi
}

# nvcc derives its CUDA toolkit root from argv[0].  A raw symlink in
# /usr/local/bin therefore makes it search /usr/local/include instead of the
# image's /usr/local/cuda/include.  Keep the convenient PATH entry, but exec
# the canonical driver so argv[0] still identifies the real toolkit tree.
write_nvcc_wrapper() {
  nvcc_real=$1
  if [ "$MODE" = dry-run ]; then
    printf 'WRITE_NVCC_WRAPPER %s -> %s\n' /usr/local/bin/nvcc "$nvcc_real"
    return
  fi
  nvcc_wrapper_tmp="/usr/local/bin/.nvcc.metaflip.$$"
  printf '%s\n' '#!/bin/sh' "exec \"$nvcc_real\" \"\$@\"" > "$nvcc_wrapper_tmp"
  chmod 0755 "$nvcc_wrapper_tmp"
  mv -f "$nvcc_wrapper_tmp" /usr/local/bin/nvcc
}

if [ "$MODE" != dry-run ] && [ "$(id -u)" -ne 0 ]; then
  echo "setup_runpod.sh: run as root inside the Runpod container" >&2
  exit 1
fi

# shellcheck disable=SC2086
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
# shellcheck disable=SC2086
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $BASE_PACKAGES
run_cmd install -d /usr/share/keyrings /etc/apt/sources.list.d /usr/local/bin
run_cmd curl -fsSL "$LLVM_KEY_URL" -o "$LLVM_KEY"
write_llvm_source
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
# shellcheck disable=SC2086
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $LLVM_PACKAGES

run_cmd ln -sfn "/usr/bin/clang-$LLVM_MAJOR" /usr/local/bin/clang
run_cmd ln -sfn "/usr/bin/clang++-$LLVM_MAJOR" /usr/local/bin/clang++
run_cmd ln -sfn "/usr/bin/ld.lld-$LLVM_MAJOR" /usr/local/bin/ld.lld

if [ "$MODE" = dry-run ]; then
  write_nvcc_wrapper /usr/local/cuda/bin/nvcc
  printf 'CHECK setup_runpod.sh --check\n'
  exit
fi

nvcc_path=$(find_nvcc || true)
if [ -z "$nvcc_path" ]; then
  echo "setup_runpod.sh: CUDA-devel image has no nvcc; refusing a host-only setup" >&2
  exit 1
fi
nvcc_real=$(readlink -f "$nvcc_path" 2>/dev/null || printf '%s\n' "$nvcc_path")
if [ -z "$nvcc_real" ] || [ ! -x "$nvcc_real" ]; then
  echo "setup_runpod.sh: cannot resolve the CUDA compiler: $nvcc_path" >&2
  exit 1
fi
write_nvcc_wrapper "$nvcc_real"

check_toolchain
