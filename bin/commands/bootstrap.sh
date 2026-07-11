#!/usr/bin/env bash
# tungsten bootstrap — host path to a working stage-1 compiler (no Ruby)
#
# Builds:
#   1. implementations/c (stage-0 C VM)
#   2. a runtime archive for linking
#   3. stage-1 compiler via the C VM → bin/tungsten-compiler
#   4. bin/tungsten.wc (Argon CLI) when possible
#
# Does NOT replace `tungsten build` (stage1+stage2 fixed-point, bits, caches).
# Use bootstrap on a fresh clone; use build for the full self-host pipeline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: tungsten bootstrap [--force]

  Build a stage-1 compiler without Ruby (C VM host path).

  1. Run doctor (toolchain check)
  2. Build implementations/c (stage 0)
  3. Build a runtime archive
  4. Compile stage 1 → bin/tungsten-compiler
  5. Compile bin/tungsten.w → bin/tungsten.wc

  Full self-host (stage1 + stage2 identity, bits) remains:
    bin/tungsten build
EOF
      exit 0
      ;;
  esac
done

color=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then color=1; fi
bold=""; dim=""; green=""; red=""; reset=""
if [ "$color" -eq 1 ]; then
  bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'
  red=$'\033[31m'; reset=$'\033[0m'
fi

log()  { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$bold" "$*" "$reset"; }
ok()   { printf '    %s%s%s %s\n' "$green" "$1" "$reset" "${2:-}"; }
die()  { printf '%serror:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

C_INTERP_DIR="$ROOT/implementations/c"
C_INTERP="$C_INTERP_DIR/build/tungsten-c"
COMPILER_W="$ROOT/compiler/tungsten.w"
COMPILER_BIN="$ROOT/bin/tungsten-compiler"
CACHE="$ROOT/build/cache"
RUNTIME_DIR="$ROOT/runtime"
RUNTIME_A="$CACHE/bootstrap-runtime.a"
STAGE1="$CACHE/bootstrap-stage1"
mkdir -p "$CACHE"

# ── 1. Doctor ───────────────────────────────────────────────────
step "Doctor"
if ! bash "$ROOT/bin/commands/doctor.sh"; then
  die "doctor reported missing tools — fix them, then re-run bootstrap"
fi

# ── 2. Stage 0: C VM ────────────────────────────────────────────
step "Stage 0: C VM (implementations/c)"
if [ "$FORCE" -eq 0 ] && [ -x "$C_INTERP" ]; then
  ok "CACHED" "$C_INTERP"
else
  log_path="/tmp/tungsten-bootstrap-c-vm.log"
  if ! make -C "$C_INTERP_DIR" >"$log_path" 2>&1; then
    cat "$log_path" >&2
    die "failed to build C VM (make -C implementations/c)"
  fi
  ok "built" "$C_INTERP"
fi
[ -x "$C_INTERP" ] || die "C VM missing at $C_INTERP"

# ── 3. Runtime archive ──────────────────────────────────────────
step "Runtime archive"
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin) EVENT_SRC=event_kqueue.c; METAL_SRCS="metal.m blas_bridge.c" ;;
  Linux)  EVENT_SRC=event_epoll.c;  METAL_SRCS="" ;;
  *)      EVENT_SRC=event_epoll.c;  METAL_SRCS="" ;;
esac

RUNTIME_SRCS=(runtime.c ssmr_witness.c lexchar_tables.c tls_stub.c aks.c slab_zstd.c "$EVENT_SRC")
# shellcheck disable=SC2206
for m in $METAL_SRCS; do RUNTIME_SRCS+=("$m"); done

need_runtime=1
if [ "$FORCE" -eq 0 ] && [ -f "$RUNTIME_A" ]; then
  need_runtime=0
  for src in "${RUNTIME_SRCS[@]}"; do
    if [ "$RUNTIME_DIR/$src" -nt "$RUNTIME_A" ]; then
      need_runtime=1
      break
    fi
  done
fi

if [ "$need_runtime" -eq 0 ]; then
  ok "CACHED" "$RUNTIME_A"
else
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bootstrap-rt.XXXXXX")"
  trap 'rm -rf "$tmpdir"' EXIT

  zstd_cflags="$(pkg-config --cflags libzstd 2>/dev/null || true)"
  if [ -z "$zstd_cflags" ] && [ -f /opt/homebrew/include/zstd.h ]; then
    zstd_cflags="-I/opt/homebrew/include"
  fi
  zstd_libs="$(pkg-config --libs libzstd 2>/dev/null || true)"
  if [ -z "$zstd_libs" ]; then
    if [ -f /opt/homebrew/lib/libzstd.a ] || [ -f /opt/homebrew/lib/libzstd.dylib ]; then
      zstd_libs="-L/opt/homebrew/lib -lzstd"
    else
      zstd_libs="-lzstd"
    fi
  fi

  cflags=(-O2 -DNDEBUG -pthread $zstd_cflags)
  if [ "$UNAME_S" = Linux ]; then
    cflags+=(-D_DEFAULT_SOURCE)
  fi

  objs=()
  for src in "${RUNTIME_SRCS[@]}"; do
    base="$(basename "$src")"
    obj="$tmpdir/${base%.*}.o"
    if [[ "$src" == *.m ]]; then
      clang -O2 -DNDEBUG -c -x objective-c "$RUNTIME_DIR/$src" -o "$obj" \
        || die "failed to compile runtime/$src"
    else
      clang "${cflags[@]}" -c "$RUNTIME_DIR/$src" -o "$obj" \
        || die "failed to compile runtime/$src"
    fi
    objs+=("$obj")
  done

  ar rcs "$RUNTIME_A" "${objs[@]}"
  ranlib "$RUNTIME_A" 2>/dev/null || true
  ok "built" "$RUNTIME_A"
  rm -rf "$tmpdir"
  trap - EXIT
fi

# ── 4. Stage 1: C VM compiles the compiler ──────────────────────
step "Stage 1: C VM compiles compiler/tungsten.w"
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_CLANG_OPT="${TUNGSTEN_CLANG_OPT:--O0}"

# Always resolve zstd link flags here: the CACHED runtime path never sets
# zstd_libs, and `set -u` rejects ${VAR:-$zstd_libs} when zstd_libs is unbound.
if [ -z "${zstd_libs:-}" ]; then
  zstd_libs="$(pkg-config --libs libzstd 2>/dev/null || true)"
  if [ -z "$zstd_libs" ]; then
    if [ -f /opt/homebrew/lib/libzstd.a ] || [ -f /opt/homebrew/lib/libzstd.dylib ]; then
      zstd_libs="-L/opt/homebrew/lib -lzstd"
    else
      zstd_libs="-lzstd"
    fi
  fi
fi
if [ -z "${TUNGSTEN_ZSTD_LDFLAGS:-}" ]; then
  export TUNGSTEN_ZSTD_LDFLAGS="$zstd_libs"
fi

stage1_log="/tmp/tungsten-bootstrap-stage1.log"
rm -f "$STAGE1" "$STAGE1.ll"
# tungsten-c <compiler.w> compile <compiler.w> --out … --runtime … --no-lto
if ! "$C_INTERP" "$COMPILER_W" compile "$COMPILER_W" \
    --out "$STAGE1" --native \
    --runtime "$RUNTIME_A" --no-lto \
    >"$stage1_log" 2>&1; then
  cat "$stage1_log" >&2
  die "stage 1 (C VM) failed — see $stage1_log"
fi

if [ "$(uname -s)" = Darwin ]; then
  codesign --force -s - "$STAGE1" >/dev/null 2>&1 || true
fi
ok "built" "$STAGE1"

# ── 5. Install compiler ─────────────────────────────────────────
step "Install bin/tungsten-compiler"
tmp_bin="$COMPILER_BIN.tmp-$$"
cp "$STAGE1" "$tmp_bin"
chmod 755 "$tmp_bin"
if [ "$(uname -s)" = Darwin ]; then
  codesign --force -s - "$tmp_bin" >/dev/null 2>&1 || true
fi
mv "$tmp_bin" "$COMPILER_BIN"
if [ -f "$STAGE1.sidemap" ]; then
  cp "$STAGE1.sidemap" "$COMPILER_BIN.sidemap"
fi
ok "installed" "$COMPILER_BIN"

# ── 6. Tungsten CLI (Argon) ─────────────────────────────────────
step "CLI: bin/tungsten.wc"
WC="$ROOT/bin/tungsten.w"
WC_OUT="$ROOT/bin/tungsten.wc"
if [ -f "$WC" ]; then
  if BIT_HOME="$ROOT/bits" TUNGSTEN_ROOT="$ROOT" \
      "$COMPILER_BIN" compile "$WC" --out "$WC_OUT" --no-lto \
      >/tmp/tungsten-bootstrap-cli.log 2>&1; then
    if [ "$(uname -s)" = Darwin ]; then
      codesign --force -s - "$WC_OUT" >/dev/null 2>&1 || true
    fi
    ok "built" "$WC_OUT"
  else
    printf '    %sskipped%s CLI (see /tmp/tungsten-bootstrap-cli.log)\n' "$dim" "$reset"
  fi
fi

printf '\n%sBootstrap complete.%s\n' "$bold" "$reset"
printf '  compiler: %s\n' "$COMPILER_BIN"
printf '  next:     %sbin/tungsten doctor%s\n' "$green" "$reset"
printf '            %sbin/tungsten build%s   # full stage1+stage2 + bits\n' "$green" "$reset"
printf '            %sbin/wit%s\n' "$green" "$reset"
