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

sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    openssl dgst -sha256 | awk '{print $NF}'
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

sha256_path() {
  if [ -f "$1" ]; then sha256_file "$1"; else printf 'missing'; fi
}

tool_identity() {
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
# Explicit CFLAGS: -O2 + native, no -g (stage0 is throwaway; -g costs i-cache).
CVM_CFLAGS="-O2 -DNDEBUG -std=c11"
if [ "$(uname -s)" = Darwin ]; then
  CVM_CFLAGS="$CVM_CFLAGS -march=native -mtune=native"
else
  CVM_CFLAGS="$CVM_CFLAGS -mtune=generic"
fi
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
  if ! make -B "${MAKE_JOB_ARGS[@]}" -C "$C_INTERP_DIR" \
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
  Linux)  EVENT_SRC=event_epoll.c;  METAL_SRCS="" ;;
  *)      EVENT_SRC=event_epoll.c;  METAL_SRCS="" ;;
esac

RUNTIME_SRCS=(runtime.c terminal_input.c ssmr_witness.c lexchar_tables.c tls_stub.c aks.c slab_zstd.c "$EVENT_SRC")
# shellcheck disable=SC2206
for m in $METAL_SRCS; do RUNTIME_SRCS+=("$m"); done

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
if [ "$UNAME_S" = Linux ]; then cflags+=(-D_DEFAULT_SOURCE); fi
runtime_objc_flags=(-O2 -DNDEBUG -c -x objective-c)

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
need_runtime=1
if [ "$FORCE" -eq 0 ] && [ -f "$RUNTIME_A" ]; then need_runtime=0; fi

if [ "$need_runtime" -eq 0 ]; then
  ok "CACHED" "$RUNTIME_A"
else
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bootstrap-rt.XXXXXX")"
  runtime_publish="$RUNTIME_A.tmp-$$"
  trap 'rm -rf "$tmpdir"; rm -f "$runtime_publish"' EXIT

  objs=()
  compile_pids=()
  compile_names=()
  wait_compile_batch() {
    batch_failed=0
    for i in "${!compile_pids[@]}"; do
      if ! wait "${compile_pids[$i]}"; then
        printf '%serror:%s failed to compile runtime/%s\n' \
          "$red" "$reset" "${compile_names[$i]}" >&2
        batch_failed=1
      fi
    done
    compile_pids=()
    compile_names=()
    [ "$batch_failed" -eq 0 ]
  }
  for src in "${RUNTIME_SRCS[@]}"; do
    base="$(basename "$src")"
    obj="$tmpdir/${base%.*}.o"
    if [[ "$src" == *.m ]]; then
      "$BOOTSTRAP_CC" "${runtime_objc_flags[@]}" "$RUNTIME_DIR/$src" -o "$obj" &
    else
      "$BOOTSTRAP_CC" "${cflags[@]}" -c "$RUNTIME_DIR/$src" -o "$obj" &
    fi
    compile_pids+=("$!")
    compile_names+=("$src")
    objs+=("$obj")
    if [ "${#compile_pids[@]}" -ge "$BUILD_JOBS" ]; then
      wait_compile_batch || die "runtime compilation failed"
    fi
  done
  wait_compile_batch || die "runtime compilation failed"

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
# -O0 for the stage-1 *product* link: stage1 is only used to drive stage2 /
# bootstrap install; -O1/-O2 cost ~3s wall for no bootstrap payoff.
export TUNGSTEN_CLANG_OPT="${TUNGSTEN_CLANG_OPT:--O0}"
# C-native Loader#load_program_ast (parse_ast.c). ~2–3× faster stage1 under
# the C VM. Off for `tungsten build` so stage1/stage2 keep identical ASTs.
export TUNGSTEN_C_FAST_PARSE="${TUNGSTEN_C_FAST_PARSE:-1}"

if [ -z "${TUNGSTEN_ZSTD_CFLAGS:-}" ]; then export TUNGSTEN_ZSTD_CFLAGS="$zstd_cflags"; fi
if [ -z "${TUNGSTEN_ZSTD_LDFLAGS:-}" ]; then export TUNGSTEN_ZSTD_LDFLAGS="$zstd_libs"; fi
export TUNGSTEN_CC="${TUNGSTEN_CC:-$BOOTSTRAP_CC}"
export TUNGSTEN_AR="${TUNGSTEN_AR:-$BOOTSTRAP_AR}"
export TUNGSTEN_OS="${TUNGSTEN_OS:-$UNAME_S}"
export TUNGSTEN_LEX64_TABLE="${TUNGSTEN_LEX64_TABLE:-$ROOT/languages/tungsten/tungsten.lex64}"

STAGE1_INPUTS=("$COMPILER_W" "$TUNGSTEN_LEX64_TABLE")
while IFS= read -r path; do STAGE1_INPUTS+=("$path"); done < <(
  find "$ROOT/compiler/lib" -type f -name '*.w' -print | LC_ALL=C sort
)
stage1_identity="$({
  printf '%s\n' \
    "bootstrap-stage-content-v1" \
    "$TUNGSTEN_CLANG_OPT" "$TUNGSTEN_C_FAST_PARSE" \
    "$TUNGSTEN_ZSTD_CFLAGS" "$TUNGSTEN_ZSTD_LDFLAGS" \
    "${TUNGSTEN_ONIG_CFLAGS:-}" "${TUNGSTEN_ONIG_LDFLAGS:-}" \
    "${TUNGSTEN_MARCH_ARGS:-}" "$TUNGSTEN_OS" \
    "$TOOLCHAIN_ENV_ID" \
    "$(tool_identity "$TUNGSTEN_CC")" "$(tool_identity "$TUNGSTEN_AR")" \
    "$(sha256_file "$C_INTERP")" "$(sha256_file "$RUNTIME_A")"
  for path in "${STAGE1_INPUTS[@]}"; do
    printf '%s\0%s\n' "${path#$ROOT/}" "$(sha256_file "$path")"
  done
} | sha256_stdin)"
STAGE1="$CACHE/bootstrap-stage1-$stage1_identity"
STAGE1_COMPLETE="$STAGE1.complete"
stage1_cache_complete() {
  [ -x "$STAGE1" ] && [ -f "$STAGE1_COMPLETE" ] || return 1
  case "$(cat "$STAGE1_COMPLETE")" in
    "ll=present sidemap=present")
      [ -f "$STAGE1.ll" ] && [ -f "$STAGE1.sidemap" ] ;;
    "ll=present sidemap=missing")
      [ -f "$STAGE1.ll" ] && [ ! -e "$STAGE1.sidemap" ] ;;
    "ll=missing sidemap=present")
      [ ! -e "$STAGE1.ll" ] && [ -f "$STAGE1.sidemap" ] ;;
    "ll=missing sidemap=missing")
      [ ! -e "$STAGE1.ll" ] && [ ! -e "$STAGE1.sidemap" ] ;;
    *) return 1 ;;
  esac
}
if [ "$FORCE" -eq 0 ] && stage1_cache_complete; then
  ok "CACHED" "$STAGE1"
else
  stage1_log="/tmp/tungsten-bootstrap-stage1.log"
  stage1_tmp="$CACHE/.bootstrap-stage1-$stage1_identity.$$"
  rm -f "$stage1_tmp" "$stage1_tmp.ll" "$stage1_tmp.sidemap"
  # tungsten-c <compiler.w> compile <compiler.w> --out … --runtime … --no-lto
  if ! TUNGSTEN_LL_PATH="$stage1_tmp.ll" \
    "$C_INTERP" "$COMPILER_W" compile "$COMPILER_W" \
      --out "$stage1_tmp" --native \
      --runtime "$RUNTIME_A" --no-lto \
      >"$stage1_log" 2>&1; then
    cat "$stage1_log" >&2
    die "stage 1 (C VM) failed — see $stage1_log"
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
    stage1_ll_state=present
  else
    rm -f "$STAGE1.ll"
    stage1_ll_state=missing
  fi
  if [ -f "$stage1_tmp.sidemap" ]; then
    mv "$stage1_tmp.sidemap" "$STAGE1.sidemap"
    stage1_sidemap_state=present
  else
    rm -f "$STAGE1.sidemap"
    stage1_sidemap_state=missing
  fi
  mv "$stage1_tmp" "$STAGE1"
  stage1_complete_tmp="$STAGE1_COMPLETE.$$"
  printf 'll=%s sidemap=%s\n' "$stage1_ll_state" "$stage1_sidemap_state" > "$stage1_complete_tmp"
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
