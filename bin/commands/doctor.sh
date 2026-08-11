#!/usr/bin/env bash
# tungsten doctor — toolchain check (bash; no Ruby / no compiler required)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/bin/commands/config.sh"
. "$ROOT/bin/commands/system_deps.sh"
tungsten_load_build_config
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)"
COMPILER="$ROOT/bin/tungsten-compiler"
DOCTOR_CC="${TUNGSTEN_CC:-clang}"

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

clang_major() {
  "$1" --version 2>/dev/null | head -1 | sed -E 's/.*version[[:space:]]+([0-9]+).*/\1/'
}

llvm22_candidate() {
  local candidate major llvm_prefix llvm22_prefix
  llvm_prefix="$(tungsten_homebrew_prefix llvm || true)"
  llvm22_prefix="$(tungsten_homebrew_prefix llvm@22 || true)"
  for candidate in \
    "${TUNGSTEN_CC:-}" clang-22 \
    "${llvm_prefix:+$llvm_prefix/bin/clang}" \
    "${llvm22_prefix:+$llvm22_prefix/bin/clang}"; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    major="$(clang_major "$candidate")"
    case "$major" in
      ''|*[!0-9]*) ;;
      *) if [ "$major" -ge 22 ]; then command -v "$candidate"; return 0; fi ;;
    esac
  done
  return 1
}

llvm_install_hint() {
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
      else
        llvm_prefix=""
      fi
      if [ -n "$llvm_prefix" ]; then
        printf 'brew install llvm lld; set [build] cc = %s/bin/clang in ~/.tungsten/config' "$llvm_prefix"
      else
        printf '%s' 'install Homebrew, run brew install llvm lld, then configure Homebrew clang under [build]'
      fi
      ;;
    Linux)
      distro=""
      if [ -r /etc/os-release ]; then
        distro="$(. /etc/os-release; printf '%s' "${ID:-}")"
      fi
      case "$distro" in
        ubuntu|debian) printf '%s' 'wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 22' ;;
        fedora|rhel|centos) printf '%s' 'sudo dnf install clang llvm lld' ;;
        arch|manjaro) printf '%s' 'sudo pacman -S clang llvm lld' ;;
        *) printf '%s' 'install LLVM/Clang 22+ and lld with your platform package manager' ;;
      esac
      ;;
    *) printf '%s' 'install LLVM/Clang 22+ and lld with your platform package manager' ;;
  esac
}

cpu_flag() {
  local cpu="${1:-native}"
  case "$cpu" in
    v1) cpu=x86-64-v1 ;;
    v2) cpu=x86-64-v2 ;;
    v3) cpu=x86-64-v3 ;;
    v4) cpu=x86-64-v4 ;;
  esac
  case "$cpu" in
    x86-64-v1|x86-64-v2|x86-64-v3|x86-64-v4) printf '%s' "-march=$cpu" ;;
    native)
      case "$(uname -m)" in x86_64|amd64) printf '%s' '-march=native' ;; *) printf '%s' '-mcpu=native' ;; esac
      ;;
    *) printf '%s' "-mcpu=$cpu" ;;
  esac
}

printf '%s\n\n' "$(c '\033[1m\033[33m' '✶ Tungsten Doctor')"

check "Tungsten" "$VERSION" 1

CACHE="$ROOT/build/cache"
if mkdir -p "$CACHE" 2>/dev/null && [ -d "$CACHE" ] && [ -w "$CACHE" ]; then
  check "build cache" "$CACHE" 1
else
  check "build cache" "cannot create or write $CACHE" 0
fi

# Missing stage-1 is expected on a fresh clone; bootstrap builds it.
# Report status but never fail doctor for this alone.
if [ -x "$COMPILER" ]; then
  check "Compiler" "$COMPILER" 1
else
  check "Compiler" "not built — run: bin/tungsten bootstrap" 1
fi

if tool_ok "$DOCTOR_CC"; then
  check "clang" "$($DOCTOR_CC --version 2>/dev/null | head -1) [$DOCTOR_CC]" 1
else
  check "clang" "$DOCTOR_CC not found" 0
fi

selected_major="$(clang_major "$DOCTOR_CC")"
preferred_clang="$(llvm22_candidate 2>/dev/null || true)"
case "$selected_major" in
  ''|*[!0-9]*) selected_major=0 ;;
esac
if [ "$selected_major" -lt 22 ]; then
  if [ -n "$preferred_clang" ]; then
    printf '  %s LLVM 22+ available: %s\n' "$(c '\033[36m' '→')" "$preferred_clang"
    printf '    configure: [build] cc = %s in ~/.tungsten/config\n' "$preferred_clang"
  else
    printf '  %s LLVM 22+ recommended: %s\n' "$(c '\033[36m' '→')" "$(llvm_install_hint)"
  fi
fi

configured_cpu="${TUNGSTEN_CPU:-native}"
configured_cpu_flag="$(cpu_flag "$configured_cpu")"
cpu_tmp="/tmp/tungsten-cpu-check-$$.o"
if printf 'int main(void){return 0;}\n' | "$DOCTOR_CC" "$configured_cpu_flag" -x c - -c -o "$cpu_tmp" >/dev/null 2>&1; then
  rm -f "$cpu_tmp"
  check "configured CPU" "$configured_cpu ($configured_cpu_flag)" 1
else
  rm -f "$cpu_tmp"
  check "configured CPU" "$configured_cpu unsupported by $DOCTOR_CC" 0
  if [ -n "$preferred_clang" ] && [ "$preferred_clang" != "$DOCTOR_CC" ]; then
    printf '    use LLVM 22+: [build] cc = %s\n' "$preferred_clang"
  fi
fi

if tool_ok make; then
  check "make" "ok" 1
else
  check "make" "not found" 0
fi

# Functional lld: can clang link with -fuse-ld=lld?
lld_tmp="/tmp/tungsten-lld-check-$$"
if printf 'int main(void){return 0;}' | "$DOCTOR_CC" -fuse-ld=lld -x c - -o "$lld_tmp" >/dev/null 2>&1; then
  rm -f "$lld_tmp"
  check "lld (clang -fuse-ld=lld)" "ok" 1
else
  rm -f "$lld_tmp"
  check "lld (clang -fuse-ld=lld)" "not found" 0
fi

zstd_cflags="$(pkg-config --cflags libzstd 2>/dev/null || true)"
homebrew_prefix="$(tungsten_homebrew_prefix || true)"
if [ -z "$zstd_cflags" ] && [ -n "$homebrew_prefix" ] && [ -f "$homebrew_prefix/include/zstd.h" ]; then
  zstd_cflags="-I$homebrew_prefix/include"
fi
if printf '#include <zstd.h>\n' | "$DOCTOR_CC" $zstd_cflags -E -x c - >/dev/null 2>&1; then
  check "libzstd (zstd.h)" "ok" 1
else
  check "libzstd (optional)" "not found — compressed string slabs disabled" 1
fi

# Linux native links compile runtime/openblas_bridge.c only when IR needs BLAS
# (@w_blas_*). Probe the exact header/library spelling used by the compiler;
# OpenBLAS is optional for an ordinary bootstrap but required by those numeric
# programs. macOS uses Accelerate instead.
if [ "$(uname -s)" = Linux ]; then
  cblas_tmp="/tmp/tungsten-cblas-check-$$"
  if printf '#include <cblas.h>\nint main(void){return cblas_sdot(0, 0, 1, 0, 1) != 0.0f;}\n' \
       | "$DOCTOR_CC" -x c - -lopenblas -o "$cblas_tmp" \
         >/dev/null 2>&1; then
    rm -f "$cblas_tmp"
    check "OpenBLAS (cblas.h)" "ok" 1
  else
    rm -f "$cblas_tmp"
    if printf '#include <cblas.h>\n' | "$DOCTOR_CC" -E -x c - >/dev/null 2>&1; then
      check "OpenBLAS (optional)" "header found, -lopenblas unavailable" 1
    else
      check "OpenBLAS (optional)" "not installed — BLAS programs need libopenblas-dev" 1
    fi
  fi
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
