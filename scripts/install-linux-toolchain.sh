#!/usr/bin/env bash
# Install the Linux build toolchain on Debian or Ubuntu: Clang, lld, the LLVM
# tools and compiler-rt from apt.llvm.org at one pinned major, plus make and
# pkg-config. CI, the release matrix and the Dockerfile all call this script,
# so the compiler that tests a commit is the compiler that builds its release.
#
# The distribution's own `clang` package is whatever that release froze
# (Ubuntu 24.04: LLVM 18), which is older than the LLVM 22 `tungsten doctor`
# asks for.
#
#   scripts/install-linux-toolchain.sh [LLVM-MAJOR] [extra apt packages...]
#
# The tools land in /usr/lib/llvm-MAJOR/bin under their plain names (clang,
# ld.lld, llvm-ar, llvm-profdata). Under GitHub Actions that directory is
# appended to GITHUB_PATH; any other caller puts it on PATH itself. It is the
# last line this script prints.
set -euo pipefail

LLVM_VERSION="${1:-22}"
if [ "$#" -gt 0 ]; then shift; fi
case "$LLVM_VERSION" in
  ''|*[!0-9]*)
    printf 'usage: %s [LLVM-MAJOR] [extra apt packages...]\n' "$0" >&2
    exit 2
    ;;
esac

if [ "$(uname -s)" != Linux ] || ! command -v apt-get >/dev/null 2>&1; then
  printf '%s: needs a Debian or Ubuntu host (apt-get)\n' "$0" >&2
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
export DEBIAN_FRONTEND=noninteractive

codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
if [ -z "$codename" ]; then
  printf '%s: /etc/os-release names no VERSION_CODENAME\n' "$0" >&2
  exit 1
fi

$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends ca-certificates wget make pkg-config "$@"

# apt reads an ASCII-armored key directly when the file ends in .asc, and
# signed-by scopes that key to this one repository.
keyring=/usr/share/keyrings/apt.llvm.org.asc
wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | $SUDO tee "$keyring" >/dev/null
printf 'deb [signed-by=%s] https://apt.llvm.org/%s/ llvm-toolchain-%s-%s main\n' \
  "$keyring" "$codename" "$codename" "$LLVM_VERSION" |
  $SUDO tee "/etc/apt/sources.list.d/llvm-toolchain-$LLVM_VERSION.list" >/dev/null
$SUDO apt-get update

# libclang-rt carries the sanitizer and profile runtimes (the C VM sanitizer
# job and --pgo builds link them); clang only recommends it.
$SUDO apt-get install -y --no-install-recommends \
  "clang-$LLVM_VERSION" "lld-$LLVM_VERSION" "llvm-$LLVM_VERSION" "libclang-rt-$LLVM_VERSION-dev"

bin="/usr/lib/llvm-$LLVM_VERSION/bin"
for tool in clang ld.lld llvm-ar llvm-profdata; do
  if [ ! -x "$bin/$tool" ]; then
    printf '%s: %s is missing after the install\n' "$0" "$bin/$tool" >&2
    exit 1
  fi
done

# The same probe `tungsten doctor` runs: this clang links through this lld.
probe="$(mktemp "${TMPDIR:-/tmp}/tungsten-toolchain.XXXXXX")"
if ! printf 'int main(void){return 0;}\n' | "$bin/clang" -fuse-ld=lld -x c - -o "$probe" || ! "$probe"; then
  rm -f "$probe"
  printf '%s: %s cannot link and run a program through lld\n' "$0" "$bin/clang" >&2
  exit 1
fi
rm -f "$probe"

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$bin" >> "$GITHUB_PATH"
fi
"$bin/clang" --version | head -n 1
printf '%s\n' "$bin"
