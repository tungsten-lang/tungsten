#!/usr/bin/env bash
# bin/commands/bootstrap.sh — fresh-clone path to the self-hosted compiler.
# Reached as `bin/tungsten bootstrap`.
#
# Builds:
#   1. implementations/c (stage-0 C VM)
#   2. a runtime archive for linking
#   3. stage-1 compiler via the C VM → bin/tungsten-compiler
#   4. bin/tungsten.wc (Argon CLI) when possible
#
# Afterwards this compiles the Tungsten build orchestrator
# (bin/commands/build.w) with the stage-1 compiler just built and execs
# it for the stage1+stage2 fixed-point + bits pipeline, so one bootstrap
# ends with the full self-host pipeline. No Ruby anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
. "$ROOT/bin/commands/bootstrap_helpers.sh"
. "$ROOT/bin/commands/config.sh"
tungsten_load_build_config

FORCE=0
RELEASE=0
PORTABLE=0
DEBUG_REQUESTED=0
NO_DEBUG_REQUESTED=0
NO_BITS=0
CPU_ARG=""
TARGET_TRIPLE=""
TARGET_SYSROOT=""
set_value_opt() {
  case "$1" in
    --cpu) CPU_ARG="$2" ;;
    --target) TARGET_TRIPLE="$2" ;;
    --sysroot) TARGET_SYSROOT="$2" ;;
  esac
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1 ;;
    --release) RELEASE=1 ;;
    --debug) DEBUG_REQUESTED=1 ;;
    --no-debug) NO_DEBUG_REQUESTED=1 ;;
    --no-bits) NO_BITS=1 ;;
    --native) CPU_ARG=native ;;
    --cpu|--target|--sysroot)
      [ "$#" -ge 2 ] || { printf 'error: %s requires a value\n' "$1" >&2; exit 1; }
      set_value_opt "$1" "$2"
      shift
      ;;
    --cpu=*|--target=*|--sysroot=*) set_value_opt "${1%%=*}" "${1#*=}" ;;
    --portable) PORTABLE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: tungsten bootstrap [options]

  Build the compiler from a fresh clone (C VM host path).

  1. Run doctor (toolchain check)
  2. Build implementations/c (stage 0)
  3. Build a runtime archive
  4. Compile stage 1 → bin/tungsten-compiler
  5. Compile bin/tungsten.w → bin/tungsten.wc
  6. Compile bin/commands/build.w and exec it — the full `tungsten build`
     pipeline (stage1 + stage2 identity, bits). No Ruby anywhere.

Options:
  --force          Ignore cached bootstrap artifacts
  --no-bits        Skip compiling bit entry points in the chained build
  --release        -O3, full LTO, no dev checks, reduced metadata
  --debug          Include symbols, safety checks, and runtime metadata
  --no-debug       Omit debug symbols and development checks
  --cpu CPU        Target CPU (v1/v2/v3/v4/native aliases accepted)
  --native         Shorthand for --cpu native
  --target TRIPLE  Build an artifact for another target
  --portable       Build x86-64-v2 and x86-64-v3 release artifacts
EOF
      exit 0
      ;;
    *) printf 'error: unknown bootstrap option: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

if [ "$DEBUG_REQUESTED" -eq 1 ] && [ "$NO_DEBUG_REQUESTED" -eq 1 ]; then
  printf 'error: --debug and --no-debug are mutually exclusive\n' >&2
  exit 1
fi
if [ "$PORTABLE" -eq 1 ] && [ -n "$CPU_ARG" ]; then
  printf 'error: --portable selects x86-64-v2/v3 and cannot be combined with --cpu/--native\n' >&2
  exit 1
fi
if [ -n "$TARGET_TRIPLE" ] && [ "$CPU_ARG" = native ]; then
  printf 'error: --target cannot be combined with --native; name a target CPU with --cpu\n' >&2
  exit 1
fi
if [ -n "$TARGET_SYSROOT" ] && [ -z "$TARGET_TRIPLE" ]; then
  printf 'error: --sysroot requires --target\n' >&2
  exit 1
fi
if [ "$RELEASE" -eq 1 ] || [ "$PORTABLE" -eq 1 ]; then
  DEBUG_ENABLED=0
else
  DEBUG_ENABLED=1
fi
if [ "$DEBUG_REQUESTED" -eq 1 ]; then DEBUG_ENABLED=1; fi
if [ "$NO_DEBUG_REQUESTED" -eq 1 ]; then DEBUG_ENABLED=0; fi

normalize_cpu() {
  case "$1" in
    v1|v2|v3|v4) printf 'x86-64-%s' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

if [ -n "$TARGET_TRIPLE" ]; then
  HOST_CPU="$(normalize_cpu "${TUNGSTEN_CPU:-native}")"
else
  HOST_CPU="$(normalize_cpu "${CPU_ARG:-${TUNGSTEN_CPU:-native}}")"
fi
case "$HOST_CPU" in
  ''|*[!A-Za-z0-9_.+-]*) printf 'error: invalid CPU name: %s\n' "$HOST_CPU" >&2; exit 1 ;;
esac
HOST_CPU_FLAGS=()
case "$HOST_CPU" in
  x86-64-v1|x86-64-v2|x86-64-v3|x86-64-v4)
    HOST_CPU_FLAGS=("-march=$HOST_CPU" -mtune=generic)
    ;;
  native)
    case "$(uname -m)" in
      x86_64|amd64) HOST_CPU_FLAGS=(-march=native -mtune=native) ;;
      *) HOST_CPU_FLAGS=(-mcpu=native) ;;
    esac
    ;;
  *) HOST_CPU_FLAGS=("-mcpu=$HOST_CPU") ;;
esac
export TUNGSTEN_MARCH_ARGS="${HOST_CPU_FLAGS[*]}"
STAGE_FLAGS=(--cpu "$HOST_CPU")
if [ "$RELEASE" -eq 1 ]; then STAGE_FLAGS+=(--release); fi
if [ "$DEBUG_ENABLED" -eq 1 ]; then
  STAGE_FLAGS+=(--debug)
else
  STAGE_FLAGS+=(--no-debug)
fi

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

disable_zstd="${TUNGSTEN_BOOTSTRAP_DISABLE_ZSTD:-0}"
case "$disable_zstd" in
  0|1) ;;
  *) die "TUNGSTEN_BOOTSTRAP_DISABLE_ZSTD must be 0 or 1" ;;
esac

# Pick the hash tool once; shasum/sha256sum print "<hash> <name>", openssl
# prints "SHA2-256(name)= <hash>" — hence the per-tool awk field.
if command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$@" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$@" | awk '{print $1}'; }
else
  sha256() { openssl dgst -sha256 "$@" | awk '{print $NF}'; }
fi
sha256_stdin() { sha256; }
sha256_file()  { sha256 "$1"; }
sha256_path()  { if [ -f "$1" ]; then sha256 "$1"; else printf 'missing'; fi; }

tool_identity() {
  local tool_path tool_version
  tool_path="$(command -v "$1" 2>/dev/null || printf '%s' "$1")"
  tool_version="$("$1" --version 2>/dev/null | head -n 1 || true)"
  printf '%s|%s' "$tool_path" "$tool_version"
}

C_INTERP_DIR="$ROOT/implementations/c"
C_INTERP_DEFAULT="$C_INTERP_DIR/build/tungsten-c"
C_INTERP="$C_INTERP_DEFAULT"
COMPILER_W="$ROOT/compiler/tungsten.w"
COMPILER_BIN="$ROOT/bin/tungsten-compiler"
CACHE="$ROOT/build/cache"
RUNTIME_DIR="$ROOT/runtime"
RUNTIME_A=""
STAGE1=""
BOOTSTRAP_CC="${TUNGSTEN_CC:-clang}"
BOOTSTRAP_AR="${TUNGSTEN_AR:-ar}"
TOOLCHAIN_ENV_ID="${SDKROOT:-}|${MACOSX_DEPLOYMENT_TARGET:-}|${CPATH:-}|${C_INCLUDE_PATH:-}|${CPLUS_INCLUDE_PATH:-}|${LIBRARY_PATH:-}|${PKG_CONFIG_PATH:-}|${PKG_CONFIG_LIBDIR:-}"
mkdir -p "$CACHE"

BUILD_JOBS="${TUNGSTEN_BUILD_JOBS:-}"
if [ -z "$BUILD_JOBS" ]; then
  BUILD_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
fi
case "$BUILD_JOBS" in
  ''|*[!0-9]*) BUILD_JOBS=4 ;;
esac
if [ "$BUILD_JOBS" -lt 1 ]; then BUILD_JOBS=1; fi
if [ "$BUILD_JOBS" -gt 8 ]; then BUILD_JOBS=8; fi
MAKE_JOB_ARGS=(-j "$BUILD_JOBS")
case " ${MAKEFLAGS:-} " in
  *" --jobserver"*|*" -j"*) MAKE_JOB_ARGS=() ;;
esac

# ── 1. Doctor ───────────────────────────────────────────────────
step "Doctor"
if ! bash "$ROOT/bin/commands/doctor.sh"; then
  die "doctor reported missing tools — fix them, then re-run bootstrap"
fi

# ── 2. Stage 0: C VM ────────────────────────────────────────────
step "Stage 0: C VM (implementations/c)"
# Stage 0 is a host tool, but it must use the same configured CPU as the
# runtime/compiler products so cache identities and local tuning agree.
CVM_CFLAGS="-O2 -DNDEBUG -std=c11 ${HOST_CPU_FLAGS[*]}"
CVM_INPUTS=()
while IFS= read -r path; do CVM_INPUTS+=("$path"); done < <(
  find "$C_INTERP_DIR/src" "$C_INTERP_DIR/include" -type f \
    \( -name '*.c' -o -name '*.inc' -o -name '*.h' \) -print | LC_ALL=C sort
)
CVM_INPUTS+=("$C_INTERP_DIR/Makefile" "$RUNTIME_DIR/wvalue.h" "$RUNTIME_DIR/w_lexchar_cache.c")
cvm_config_identity="$({
  printf '%s\n%s\n%s\n' "$CVM_CFLAGS" "$(tool_identity "$BOOTSTRAP_CC")" \
    "${CPPFLAGS:-}|${ARCH_FLAGS:-}|${LDFLAGS:-}|$TOOLCHAIN_ENV_ID"
} | sha256_stdin)"
cvm_identity="$({
  printf '%s\n' "$cvm_config_identity"
  for path in "${CVM_INPUTS[@]}"; do
    printf '%s\0%s\n' "${path#$ROOT/}" "$(sha256_file "$path")"
  done
} | sha256_stdin)"
CVM_CACHE_BUILD_DIR="build/bootstrap-$cvm_identity"
C_INTERP_CACHE="$C_INTERP_DIR/$CVM_CACHE_BUILD_DIR/tungsten-c"
CVM_BUILD_DIR="$CVM_CACHE_BUILD_DIR-build-$$"
C_INTERP="$C_INTERP_DIR/$CVM_BUILD_DIR/tungsten-c"
if [ "$FORCE" -eq 0 ] && [ -x "$C_INTERP_CACHE" ]; then
  C_INTERP="$C_INTERP_CACHE"
  ok "CACHED" "$C_INTERP"
else
  log_path="/tmp/tungsten-bootstrap-c-vm-$$.log"
  rm -rf "$C_INTERP_DIR/$CVM_BUILD_DIR"
  if ! make -B ${MAKE_JOB_ARGS[@]+"${MAKE_JOB_ARGS[@]}"} -C "$C_INTERP_DIR" \
      BUILD_DIR="$CVM_BUILD_DIR" CC="$BOOTSTRAP_CC" CFLAGS="$CVM_CFLAGS" \
      >"$log_path" 2>&1; then
    cat "$log_path" >&2
    rm -rf "$C_INTERP_DIR/$CVM_BUILD_DIR"
    die "failed to build C VM (make -C implementations/c)"
  fi
  mkdir -p "$(dirname "$C_INTERP_CACHE")"
  cvm_cache_tmp="$C_INTERP_CACHE.tmp-$$"
  cp "$C_INTERP" "$cvm_cache_tmp"
  chmod 755 "$cvm_cache_tmp"
  mv "$cvm_cache_tmp" "$C_INTERP_CACHE"
  rm -rf "$C_INTERP_DIR/$CVM_BUILD_DIR"
  C_INTERP="$C_INTERP_CACHE"
  ok "built" "$C_INTERP"
fi
[ -x "$C_INTERP" ] || die "C VM missing at $C_INTERP"
# Atomically refresh the conventional developer path, but never execute it in
# this bootstrap; concurrent identities use their own immutable binaries.
if ! cmp -s "$C_INTERP" "$C_INTERP_DEFAULT" 2>/dev/null; then
  cvm_publish="$C_INTERP_DEFAULT.tmp-$$"
  cp "$C_INTERP" "$cvm_publish"
  chmod 755 "$cvm_publish"
  mv "$cvm_publish" "$C_INTERP_DEFAULT"
fi

# ── 3. Runtime archive ──────────────────────────────────────────
step "Runtime archive"
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin) EVENT_SRC=event_kqueue.c; METAL_SRCS="metal.m blas_bridge.c" ;;
  *)      EVENT_SRC=event_epoll.c;  METAL_SRCS="" ;;
esac

if [ -n "${TUNGSTEN_ZSTD_CFLAGS+x}" ]; then
  zstd_cflags="$TUNGSTEN_ZSTD_CFLAGS"
else
  zstd_cflags="$(pkg-config --cflags libzstd 2>/dev/null || true)"
  if [ -z "$zstd_cflags" ] && [ -f /opt/homebrew/include/zstd.h ]; then
    zstd_cflags="-I/opt/homebrew/include"
  fi
fi

if [ -n "${TUNGSTEN_ZSTD_LDFLAGS+x}" ]; then
  zstd_libs="$TUNGSTEN_ZSTD_LDFLAGS"
  zstd_probe_libs="$zstd_libs"
else
  zstd_libs="$(pkg-config --libs libzstd 2>/dev/null || true)"
  if [ -z "$zstd_libs" ] &&
     { [ -f /opt/homebrew/lib/libzstd.a ] ||
       [ -f /opt/homebrew/lib/libzstd.dylib ]; }; then
    zstd_libs="-L/opt/homebrew/lib -lzstd"
  fi
  zstd_probe_libs="${zstd_libs:--lzstd}"
fi

zstd_available=0
if [ "$disable_zstd" -eq 0 ]; then
  # Probe the complete contract, not just the header: minimal competition
  # images may provide libzstd.so.1 without either zstd.h or the -lzstd linker
  # name supplied by the development package.
  # shellcheck disable=SC2086
  if printf '#include <zstd.h>\nint main(void){return (int)ZSTD_isError(0);}\n' |
       "$BOOTSTRAP_CC" $zstd_cflags -x c - $zstd_probe_libs -o /dev/null \
         >/dev/null 2>&1; then
    zstd_available=1
    zstd_libs="$zstd_probe_libs"
  fi
fi

if [ "$zstd_available" -eq 1 ]; then
  ZSTD_RUNTIME_SRC=slab_zstd.c
else
  # A failed probe silently downgrades to the stub only on the auto-detect
  # path. Explicitly configured zstd flags are a statement of intent: if
  # they cannot link the probe, fail loudly instead of shipping a compiler
  # whose compressed-slab support quietly vanished.
  if [ "$disable_zstd" -eq 0 ] &&
     { [ -n "${TUNGSTEN_ZSTD_CFLAGS+x}" ] || [ -n "${TUNGSTEN_ZSTD_LDFLAGS+x}" ]; }; then
    printf 'error: TUNGSTEN_ZSTD_CFLAGS/TUNGSTEN_ZSTD_LDFLAGS are set but the zstd link probe failed\n' >&2
    printf '       (cflags: %s | libs: %s)\n' "$zstd_cflags" "$zstd_probe_libs" >&2
    printf '       Fix the flags, unset them for auto-detection, or set TUNGSTEN_BOOTSTRAP_DISABLE_ZSTD=1.\n' >&2
    exit 1
  fi
  ZSTD_RUNTIME_SRC=slab_zstd_stub.c
  zstd_cflags=""
  zstd_libs=""
fi

RUNTIME_SRCS=(
  runtime.c terminal_input.c ssmr_witness.c lexchar_tables.c tls_stub.c aks.c
  "$ZSTD_RUNTIME_SRC" "$EVENT_SRC"
)
# shellcheck disable=SC2206
for m in $METAL_SRCS; do RUNTIME_SRCS+=("$m"); done

if [ "$RELEASE" -eq 1 ]; then PROFILE_OPT=-O3; else PROFILE_OPT=-O0; fi
if [ "$DEBUG_ENABLED" -eq 1 ]; then DEBUG_CFLAG=-g; else DEBUG_CFLAG=-DNDEBUG; fi
cflags=("$PROFILE_OPT" "$DEBUG_CFLAG" -pthread "${HOST_CPU_FLAGS[@]}" $zstd_cflags)
if [ "$UNAME_S" = Linux ]; then cflags+=(-D_DEFAULT_SOURCE); fi
runtime_objc_flags=("$PROFILE_OPT" "$DEBUG_CFLAG" "${HOST_CPU_FLAGS[@]}" -c -x objective-c)

RUNTIME_INPUTS=()
for src in "${RUNTIME_SRCS[@]}"; do RUNTIME_INPUTS+=("$RUNTIME_DIR/$src"); done
while IFS= read -r path; do RUNTIME_INPUTS+=("$path"); done < <(
  find "$RUNTIME_DIR" -maxdepth 1 -type f \
    \( -name '*.h' -o -name 'w_lexchar_cache.c' \) -print | LC_ALL=C sort
)
RUNTIME_INPUTS+=("$RUNTIME_DIR/w_char_table.c" "$RUNTIME_DIR/generated/bigint_thresholds.h")
runtime_identity="$({
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "bootstrap-runtime-v1" "$UNAME_S" "${cflags[*]}" "${runtime_objc_flags[*]}" \
    "$(tool_identity "$BOOTSTRAP_CC")" "$(tool_identity "$BOOTSTRAP_AR")" \
    "$TOOLCHAIN_ENV_ID"
  for path in "${RUNTIME_INPUTS[@]}"; do
    printf '%s\0%s\n' "${path#$ROOT/}" "$(sha256_path "$path")"
  done
} | sha256_stdin)"
RUNTIME_A="$CACHE/bootstrap-runtime-$runtime_identity.a"

if [ "$FORCE" -eq 0 ] && [ -f "$RUNTIME_A" ]; then
  ok "CACHED" "$RUNTIME_A"
else
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bootstrap-rt.XXXXXX")"
  runtime_publish="$RUNTIME_A.tmp-$$"
  trap 'rm -rf "$tmpdir"; rm -f "$runtime_publish"' EXIT

  # The full source set is at most ~9 files; compile them all concurrently
  # and gate on the slowest.
  objs=()
  compile_pids=()
  compile_names=()
  for src in "${RUNTIME_SRCS[@]}"; do
    obj="$tmpdir/${src%.*}.o"
    if [[ "$src" == *.m ]]; then
      "$BOOTSTRAP_CC" "${runtime_objc_flags[@]}" "$RUNTIME_DIR/$src" -o "$obj" &
    else
      "$BOOTSTRAP_CC" "${cflags[@]}" -c "$RUNTIME_DIR/$src" -o "$obj" &
    fi
    compile_pids+=("$!")
    compile_names+=("$src")
    objs+=("$obj")
  done
  compile_failed=0
  for i in "${!compile_pids[@]}"; do
    if ! wait "${compile_pids[$i]}"; then
      printf '%serror:%s failed to compile runtime/%s\n' \
        "$red" "$reset" "${compile_names[$i]}" >&2
      compile_failed=1
    fi
  done
  [ "$compile_failed" -eq 0 ] || die "runtime compilation failed"

  tmp_archive="$tmpdir/$(basename "$RUNTIME_A")"
  "$BOOTSTRAP_AR" rcs "$tmp_archive" "${objs[@]}"
  cp "$tmp_archive" "$runtime_publish"
  mv "$runtime_publish" "$RUNTIME_A"
  ok "built" "$RUNTIME_A"
  rm -rf "$tmpdir"
  trap - EXIT
fi

# ── 4. Stage 1: C VM compiles the compiler ──────────────────────
# Hot path is load+parse of ~45k lines of compiler .w (~4s) then lowering
# (~2s). Flag knobs on the C VM (-O3/PGO/LTO) move this by noise (~0–2%).
# Link of stage1 with -O0 is ~1.5s; -O1/-O2 add ~3s for a throwaway binary.
# Skip entirely when the installed compiler is already newer than its inputs.
step "Stage 1: C VM compiles compiler/tungsten.w"
export TUNGSTEN_ROOT="$ROOT"
# The public profile controls the product; release is -O3, otherwise bootstrap
# stays quick at -O0. --debug layers symbols onto either profile.
bootstrap_product_opt="$PROFILE_OPT"
if [ "$DEBUG_ENABLED" -eq 1 ]; then bootstrap_product_opt="$bootstrap_product_opt -g"; fi
export TUNGSTEN_CLANG_OPT="${TUNGSTEN_CLANG_OPT:-$bootstrap_product_opt}"
# C-native Loader#load_program_ast (parse_ast.c). ~2–3× faster stage1 under
# the C VM. Off for `tungsten build` so stage1/stage2 keep identical ASTs.
export TUNGSTEN_C_FAST_PARSE="${TUNGSTEN_C_FAST_PARSE:-1}"

export TUNGSTEN_ZSTD_CFLAGS="$zstd_cflags"
export TUNGSTEN_ZSTD_LDFLAGS="$zstd_libs"
export TUNGSTEN_CC="${TUNGSTEN_CC:-$BOOTSTRAP_CC}"
export TUNGSTEN_AR="${TUNGSTEN_AR:-$BOOTSTRAP_AR}"
export TUNGSTEN_OS="${TUNGSTEN_OS:-$UNAME_S}"
export TUNGSTEN_LEX64_TABLE="${TUNGSTEN_LEX64_TABLE:-$ROOT/languages/tungsten/tungsten.lex64}"

stage1_identity="$({
  printf '%s\n' \
    "bootstrap-stage-content-v3" \
    "$TUNGSTEN_CLANG_OPT" "$TUNGSTEN_C_FAST_PARSE" \
    "$TUNGSTEN_ZSTD_CFLAGS" "$TUNGSTEN_ZSTD_LDFLAGS" \
    "${TUNGSTEN_ONIG_CFLAGS:-}" "${TUNGSTEN_ONIG_LDFLAGS:-}" \
    "${TUNGSTEN_MARCH_ARGS:-}" "$TUNGSTEN_OS" \
    "$TOOLCHAIN_ENV_ID" \
    "$(tool_identity "$TUNGSTEN_CC")" "$(tool_identity "$TUNGSTEN_AR")" \
    "$(sha256_file "$C_INTERP")" "$(sha256_file "$RUNTIME_A")"
  bootstrap_stage1_source_manifest \
    "$ROOT" "$COMPILER_W" "$TUNGSTEN_LEX64_TABLE"
} | sha256_stdin)"
STAGE1="$CACHE/bootstrap-stage1-$stage1_identity"
STAGE1_COMPLETE="$STAGE1.complete"
# The marker records which optional outputs (.ll/.sidemap) the cached stage-1
# build produced, so a hit is honored only when the same set is still present.
stage1_state() {
  printf 'll=%s sidemap=%s\n' \
    "$([ -f "$STAGE1.ll" ] && echo present || echo missing)" \
    "$([ -f "$STAGE1.sidemap" ] && echo present || echo missing)"
}
stage1_cache_complete() {
  [ -x "$STAGE1" ] && [ -f "$STAGE1_COMPLETE" ] || return 1
  [ "$(cat "$STAGE1_COMPLETE")" = "$(stage1_state)" ]
}
if [ "$FORCE" -eq 0 ] && stage1_cache_complete; then
  ok "CACHED" "$STAGE1"
else
  stage1_log="/tmp/tungsten-bootstrap-stage1.log"
  stage1_tmp="$CACHE/.bootstrap-stage1-$stage1_identity.$$"
  rm -f "$stage1_tmp" "$stage1_tmp.ll" "$stage1_tmp.sidemap"
  # Development bootstrap keeps the fast cached-runtime/no-LTO path. A
  # release bootstrap recompiles runtime sources into the full-LTO product.
  stage1_link_flags=()
  if [ "$RELEASE" -ne 1 ]; then
    stage1_link_flags=(--runtime "$RUNTIME_A" --no-lto)
  fi
  if ! TUNGSTEN_LL_PATH="$stage1_tmp.ll" \
      "$C_INTERP" "$COMPILER_W" compile "$COMPILER_W" \
        --out "$stage1_tmp" "${STAGE_FLAGS[@]}" \
        ${stage1_link_flags[@]+"${stage1_link_flags[@]}"} \
        >"$stage1_log" 2>&1; then
    cat "$stage1_log" >&2
    die "stage 1 (C VM) failed — see $stage1_log"
  fi
  if ! bootstrap_require_executable "$stage1_tmp" "$stage1_log" "stage 1 (C VM)"; then
    rm -f "$stage1_tmp" "$stage1_tmp.ll" "$stage1_tmp.sidemap"
    exit 1
  fi
  if [ "$UNAME_S" = Darwin ]; then
    codesign --force -s - "$stage1_tmp" >/dev/null 2>&1 || \
      die "failed to ad-hoc sign stage 1"
  fi
  # Publish the completeness marker last. Concurrent readers will either use
  # the old complete cache or rebuild; they never observe a binary whose
  # optional outputs have only been partially published.
  rm -f "$STAGE1_COMPLETE"
  if [ -f "$stage1_tmp.ll" ]; then
    mv "$stage1_tmp.ll" "$STAGE1.ll"
  else
    rm -f "$STAGE1.ll"
  fi
  if [ -f "$stage1_tmp.sidemap" ]; then
    mv "$stage1_tmp.sidemap" "$STAGE1.sidemap"
  else
    rm -f "$STAGE1.sidemap"
  fi
  mv "$stage1_tmp" "$STAGE1"
  stage1_complete_tmp="$STAGE1_COMPLETE.$$"
  stage1_state > "$stage1_complete_tmp"
  mv "$stage1_complete_tmp" "$STAGE1_COMPLETE"
  ok "built" "$STAGE1"
fi

expected_compiler_digest="$(sha256_file "$STAGE1")"
expected_compiler_sidemap="missing:sidemap"
if [ -f "$STAGE1.sidemap" ]; then expected_compiler_sidemap="$(sha256_file "$STAGE1.sidemap")"; fi
current_compiler_digest=""
if [ -x "$COMPILER_BIN" ]; then current_compiler_digest="$(sha256_file "$COMPILER_BIN")"; fi
current_compiler_sidemap="missing:sidemap"
if [ -f "$COMPILER_BIN.sidemap" ]; then current_compiler_sidemap="$(sha256_file "$COMPILER_BIN.sidemap")"; fi

if [ "$current_compiler_digest" = "$expected_compiler_digest" ] \
   && [ "$current_compiler_sidemap" = "$expected_compiler_sidemap" ]; then
  ok "CACHED" "$COMPILER_BIN (identity ${stage1_identity:0:16})"
else
  # ── 5. Install compiler ─────────────────────────────────────────
  step "Install bin/tungsten-compiler"
  tmp_bin="$COMPILER_BIN.tmp-$$"
  cp "$STAGE1" "$tmp_bin"
  chmod 755 "$tmp_bin"
  mv "$tmp_bin" "$COMPILER_BIN"
  if [ -f "$STAGE1.sidemap" ]; then
    tmp_sidemap="$COMPILER_BIN.sidemap.tmp-$$"
    cp "$STAGE1.sidemap" "$tmp_sidemap"
    mv "$tmp_sidemap" "$COMPILER_BIN.sidemap"
  else
    rm -f "$COMPILER_BIN.sidemap"
  fi
  ok "installed" "$COMPILER_BIN"
fi

# Release artifacts are emitted by the runnable host compiler after bootstrap;
# a cross-target compiler is never executed as the next bootstrap stage.
artifact_target="$TARGET_TRIPLE"
artifact_cpus=()
artifact_release="$RELEASE"
if [ "$PORTABLE" -eq 1 ]; then
  artifact_release=1
  if [ -z "$artifact_target" ]; then
    case "$UNAME_S" in
      Darwin) artifact_target=x86_64-apple-macos ;;
      *) artifact_target=x86_64-unknown-linux-gnu ;;
    esac
  fi
  case "$artifact_target" in
    x86_64-*|x86_64_*) ;;
    *) die "--portable is the x86-64 release set; target must be an x86_64 triple" ;;
  esac
  artifact_cpus=(x86-64-v2 x86-64-v3)
elif [ -n "$artifact_target" ]; then
  if [ -n "$CPU_ARG" ]; then
    artifact_cpus=("$(normalize_cpu "$CPU_ARG")")
  else
    artifact_cpus=("")
  fi
fi

if [ "${#artifact_cpus[@]}" -gt 0 ]; then
  step "Release artifacts"
  for artifact_cpu in "${artifact_cpus[@]}"; do
    cpu_label="${artifact_cpu:-default}"
    target_label="$(printf '%s' "$artifact_target" | tr -c 'A-Za-z0-9_.+-' '_')"
    artifact_dir="$ROOT/build/releases/$target_label/$cpu_label"
    artifact_bin="$artifact_dir/tungsten-compiler"
    mkdir -p "$artifact_dir"
    artifact_flags=(--target "$artifact_target")
    if [ -n "$artifact_cpu" ]; then artifact_flags+=(--cpu "$artifact_cpu"); fi
    if [ -n "$TARGET_SYSROOT" ]; then artifact_flags+=(--sysroot "$TARGET_SYSROOT"); fi
    if [ "$artifact_release" -eq 1 ]; then artifact_flags+=(--release); fi
    if [ "$artifact_release" -eq 1 ]; then artifact_opt=-O3; else artifact_opt=-O0; fi
    if [ "$DEBUG_ENABLED" -eq 1 ]; then
      artifact_flags+=(--debug)
      artifact_opt="$artifact_opt -g"
    else
      artifact_flags+=(--no-debug)
    fi
    TUNGSTEN_MARCH_ARGS="" TUNGSTEN_CLANG_OPT="$artifact_opt" \
      "$COMPILER_BIN" compile "$COMPILER_W" --out "$artifact_bin" \
      "${artifact_flags[@]}" || die "failed to build $artifact_target/$cpu_label"
    case "$artifact_target" in
      *apple*) codesign --force -s - "$artifact_bin" >/dev/null 2>&1 || die "failed to ad-hoc sign $artifact_target/$cpu_label" ;;
    esac
    ok "built" "${artifact_bin#$ROOT/}"
  done
fi

# ── 6. Tungsten CLI (Argon) ─────────────────────────────────────
step "CLI: bin/tungsten.wc"
WC="$ROOT/bin/tungsten.w"
WC_OUT="$ROOT/bin/tungsten.wc"
if [ -f "$WC" ]; then
  if [ "$FORCE" -eq 0 ] && [ -x "$WC_OUT" ] && [ ! "$WC" -nt "$WC_OUT" ] \
     && [ ! "$COMPILER_BIN" -nt "$WC_OUT" ]; then
    ok "CACHED" "$WC_OUT"
  elif BIT_HOME="$ROOT/bits" TUNGSTEN_ROOT="$ROOT" \
      "$COMPILER_BIN" compile "$WC" --out "$WC_OUT" --no-lto \
      >/tmp/tungsten-bootstrap-cli.log 2>&1; then
    if [ "$UNAME_S" = Darwin ]; then
      codesign --force -s - "$WC_OUT" >/dev/null 2>&1 || true
    fi
    ok "built" "$WC_OUT"
  else
    printf '    %sskipped%s CLI (see /tmp/tungsten-bootstrap-cli.log)\n' "$dim" "$reset"
  fi
fi

printf '\n%sStage-1 bootstrap complete.%s\n' "$bold" "$reset"
printf '  compiler: %s\n' "$COMPILER_BIN"

# ── 7. Build orchestrator + full self-host build ────────────────
# bootstrap includes `tungsten build`: compile the Tungsten build
# orchestrator (bin/commands/build.w) with the stage-1 compiler just
# built, then exec it for the stage1+stage2 fixed-point + bits pipeline.
BUILD_W="$ROOT/bin/commands/build.w"
BUILD_BIN="$ROOT/bin/commands/build"
step "Build orchestrator: bin/commands/build"
if [ -x "$BUILD_BIN" ] && [ ! "$BUILD_W" -nt "$BUILD_BIN" ] && [ ! "$COMPILER_BIN" -nt "$BUILD_BIN" ]; then
  ok "CACHED" "${BUILD_BIN#$ROOT/}"
else
  BIT_HOME="$ROOT/bits" TUNGSTEN_ROOT="$ROOT" \
    "$COMPILER_BIN" compile "$BUILD_W" --out "$BUILD_BIN" --no-lto \
    >/tmp/tungsten-bootstrap-buildw.log 2>&1 \
    || die "failed to compile bin/commands/build.w (see /tmp/tungsten-bootstrap-buildw.log)"
  if [ "$UNAME_S" = Darwin ]; then
    codesign --force -s - "$BUILD_BIN" >/dev/null 2>&1 || true
  fi
  ok "built" "${BUILD_BIN#$ROOT/}"
fi

build_flags=()
if [ "$FORCE" -eq 1 ]; then build_flags+=(--force); fi
if [ "$RELEASE" -eq 1 ]; then build_flags+=(--release); fi
if [ "$DEBUG_REQUESTED" -eq 1 ]; then build_flags+=(--debug); fi
if [ "$NO_DEBUG_REQUESTED" -eq 1 ]; then build_flags+=(--no-debug); fi
if [ "$NO_BITS" -eq 1 ]; then build_flags+=(--no-bits); fi
if [ -n "$CPU_ARG" ]; then build_flags+=(--cpu "$CPU_ARG"); fi
if [ -n "$TARGET_TRIPLE" ]; then build_flags+=(--target "$TARGET_TRIPLE"); fi
if [ -n "$TARGET_SYSROOT" ]; then build_flags+=(--sysroot "$TARGET_SYSROOT"); fi
if [ "$PORTABLE" -eq 1 ]; then build_flags+=(--portable); fi
step "Full build: stage1+stage2 + bits (tungsten build)"
exec env TUNGSTEN_ROOT="$ROOT" BIT_HOME="$ROOT/bits" \
  "$BUILD_BIN" ${build_flags[@]+"${build_flags[@]}"}
