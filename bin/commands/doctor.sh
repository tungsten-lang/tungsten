#!/usr/bin/env bash
# tungsten doctor — toolchain check (bash; no Ruby / no compiler required)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)"
COMPILER="$ROOT/bin/tungsten-compiler"

color=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  color=1
fi
if [ -n "${CLICOLOR_FORCE:-}" ]; then
  color=1
fi

c() { # c CODE text
  if [ "$color" -eq 1 ]; then
    printf '%b%s%b' "$1" "$2" '\033[0m'
  else
    printf '%s' "$2"
  fi
}

passed=0
failed=0

check() { # check NAME DETAIL OK(0/1)
  local name="$1" detail="$2" ok="$3"
  if [ "$ok" -eq 1 ]; then
    passed=$((passed + 1))
    printf '  %s %s' "$(c '\033[32m' '✓')" "$name"
    if [ -n "$detail" ]; then
      printf ' %s' "$(c '\033[36m' "$detail")"
    fi
    printf '\n'
  else
    failed=$((failed + 1))
    printf '  %s %s' "$(c '\033[91m' '✗')" "$name"
    if [ -n "$detail" ]; then
      printf ' %s' "$(c '\033[2m' "$detail")"
    fi
    printf '\n'
  fi
}

tool_ok() { command -v "$1" >/dev/null 2>&1; }

printf '%s\n\n' "$(c '\033[1m\033[33m' '✶ Tungsten Doctor')"

check "Tungsten" "$VERSION" 1

if [ -x "$COMPILER" ]; then
  check "Compiler" "$COMPILER" 1
else
  check "Compiler" "not built — run: bin/tungsten bootstrap" 0
fi

if tool_ok clang; then
  check "clang" "$(clang --version 2>/dev/null | head -1)" 1
else
  check "clang" "not found" 0
fi

if tool_ok make; then
  check "make" "ok" 1
else
  check "make" "not found" 0
fi

# Functional lld: can clang link with -fuse-ld=lld?
lld_tmp="/tmp/tungsten-lld-check-$$"
if printf 'int main(void){return 0;}' | clang -fuse-ld=lld -x c - -o "$lld_tmp" >/dev/null 2>&1; then
  rm -f "$lld_tmp"
  check "lld (clang -fuse-ld=lld)" "ok" 1
else
  rm -f "$lld_tmp"
  check "lld (clang -fuse-ld=lld)" "not found" 0
fi

zstd_cflags="$(pkg-config --cflags libzstd 2>/dev/null || true)"
if [ -z "$zstd_cflags" ] && [ -f /opt/homebrew/include/zstd.h ]; then
  zstd_cflags="-I/opt/homebrew/include"
fi
if printf '#include <zstd.h>\n' | clang $zstd_cflags -E -x c - >/dev/null 2>&1; then
  check "libzstd (zstd.h)" "ok" 1
else
  check "libzstd (zstd.h)" "not found" 0
fi

printf '\n%s\n' "$(c '\033[2m' 'Developer options (not required for normal use):')"

if tool_ok ruby; then
  check "Ruby (--ruby bootstrap)" "$(ruby -v 2>/dev/null | head -1)" 1
else
  check "Ruby (--ruby bootstrap)" "not installed" 1
fi

if tool_ok nvcc; then
  check "nvcc (CUDA)" "$(nvcc --version 2>/dev/null | tail -1)" 1
else
  check "nvcc (CUDA)" "not installed" 1
fi

if command -v xcrun >/dev/null 2>&1 && xcrun -f metal >/dev/null 2>&1; then
  check "Metal toolchain" "ok" 1
else
  check "Metal toolchain" "not on this host" 1
fi

total=$((passed + failed))
printf '\n%s\n' "$(c '\033[2m' "${passed}/${total} required checks passed")"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
exit 0
