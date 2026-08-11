#!/usr/bin/env bash
# UBSan sweep of the C runtime, in support of raising the dev-build
# optimization level off -O0 (UB that is benign at -O0 can become a
# miscompile at higher levels — surface it BEFORE the flip).
#
# What it does:
#   1. Compiles the same dev runtime source set bin/commands/build.w uses
#      into a side archive at -O2 -g -fsanitize=undefined (recoverable, so a
#      single run enumerates EVERY diagnostic instead of halting at the
#      first; set UBSAN_HALT=1 to turn the same archive into a hard gate via
#      UBSAN_OPTIONS=halt_on_error=1).
#   2. Compile-checks the env-gated network sources (tls.c, http2.c, http3.c)
#      under the same flags when their headers are installed. They are NOT in
#      default dev archives (TLS/HTTP2 env gates), so they get no runtime
#      exercise here — compile-clean at -O2 is all this step claims.
#   3. Compiles each target spec with the installed compiler against the
#      sanitized archive (--runtime <archive> --no-lto) and runs it,
#      capturing stderr per target. TUNGSTEN_CLANG_OPT carries
#      -fsanitize=undefined so clang links the UBSan runtime library.
#   4. Builds a UBSan-instrumented compiler binary and has it compile a spec
#      — exercising the SIMD lexer, slab/zstd, onig and allocator paths of
#      the runtime under the sanitizer.
#
# Usage:
#   scripts/ubsan_runtime_sweep.sh [target.w ...]
# With no arguments it sweeps spec/numeric/*.w plus
# spec/compiler/typed_overload_hosts_spec.w.
# Output: per-target logs + summary under $UBSAN_OUT
# (default /tmp/tungsten-ubsan-sweep). Exit 1 if any diagnostic or failure.

# No -u: macOS ships bash 3.2, where empty arrays read as unset.
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/bin/commands/system_deps.sh"
CC="${TUNGSTEN_CC:-clang}"
AR_TOOL="${TUNGSTEN_AR:-ar}"
COMPILER="$ROOT/bin/tungsten-compiler"
OUT="${UBSAN_OUT:-/tmp/tungsten-ubsan-sweep}"
ARCHIVE="$OUT/runtime-ubsan.a"
OPT="${UBSAN_OPT:--O2}"

SAN_CFLAGS=(-fsanitize=undefined "$OPT" -g -pthread)
UBSAN_ENV="print_stacktrace=1"
[[ "${UBSAN_HALT:-0}" == "1" ]] && UBSAN_ENV="$UBSAN_ENV:halt_on_error=1"

if [[ ! -x "$COMPILER" ]]; then
  echo "bin/tungsten-compiler is missing; run bin/tungsten build first." >&2
  exit 1
fi

mkdir -p "$OUT/obj" "$OUT/bin" "$OUT/log"
cd "$ROOT"

# ── 1. Sanitized runtime archive (same dev source set as build.w) ────────
srcs=(runtime.c terminal_input.c ssmr_witness.c lexchar_tables.c tls_stub.c aks.c)
case "$(uname -s)" in
  Darwin) srcs+=(event_kqueue.c metal.m blas_bridge.c hid_bridge.m) ;;
  Linux)  srcs+=(event_epoll.c) ;;
esac
zstd_cflags=()
homebrew_prefix="$(tungsten_homebrew_prefix || true)"
if [[ -n "$homebrew_prefix" && -f "$homebrew_prefix/include/zstd.h" ]]; then
  zstd_cflags=("-I$homebrew_prefix/include")
  srcs+=(slab_zstd.c)
else
  srcs+=(slab_zstd_stub.c)
fi
onig_cflags=()
if [[ -n "$homebrew_prefix" && -f "$homebrew_prefix/include/oniguruma.h" ]]; then
  onig_cflags=("-I$homebrew_prefix/include" -DTUNGSTEN_ONIG)
fi

echo "==> Compiling sanitized runtime archive ($OPT -fsanitize=undefined)"
objs=()
for src in "${srcs[@]}"; do
  obj="$OUT/obj/${src%.*}.o"
  flags=("${SAN_CFLAGS[@]}")
  [[ "$src" == *.m ]] && flags+=(-x objective-c)
  if ! "$CC" "${flags[@]}" "${onig_cflags[@]}" "${zstd_cflags[@]}" \
       -c "$ROOT/runtime/$src" -o "$obj" 2> "$OUT/log/cc-${src%.*}.err"; then
    echo "FAIL compile $src (see $OUT/log/cc-${src%.*}.err)" >&2
    exit 1
  fi
  [[ -s "$OUT/log/cc-${src%.*}.err" ]] && echo "  [warnings] $src -> $OUT/log/cc-${src%.*}.err"
  objs+=("$obj")
done
rm -f "$ARCHIVE"
"$AR_TOOL" rcs "$ARCHIVE" "${objs[@]}"
echo "    archive: $ARCHIVE"

# ── 2. Compile-check env-gated network sources (no runtime exercise) ─────
echo "==> Compile-checking env-gated network sources"
openssl_prefix="$(tungsten_homebrew_prefix openssl@3 || true)"
nghttp2_prefix="$(tungsten_homebrew_prefix libnghttp2 || true)"
if [[ -f "$openssl_prefix/include/openssl/ssl.h" ]]; then
  for src in tls.c http2.c http3.c; do
    [[ -f "$ROOT/runtime/$src" ]] || continue
    extra=(-DTUNGSTEN_TLS "-I$openssl_prefix/include")
    [[ -f "$nghttp2_prefix/include/nghttp2/nghttp2.h" ]] && \
      extra+=(-DTUNGSTEN_HTTP2 "-I$nghttp2_prefix/include")
    if "$CC" "${SAN_CFLAGS[@]}" "${extra[@]}" -c "$ROOT/runtime/$src" \
         -o "$OUT/obj/gated-${src%.*}.o" 2> "$OUT/log/cc-gated-${src%.*}.err"; then
      echo "    ok   $src (compile-only; not linked into default archives)"
    else
      echo "    FAIL $src (see $OUT/log/cc-gated-${src%.*}.err)" >&2
    fi
  done
else
  echo "    skipped: openssl headers not found at $openssl_prefix"
fi

# ── 3. Compile + run each target against the sanitized archive ───────────
targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=(spec/numeric/*.w spec/compiler/typed_overload_hosts_spec.w)
fi

fail=0
diag=0
echo "==> Sweeping ${#targets[@]} targets"
for path in "${targets[@]}"; do
  name="$(basename "${path%.w}")"
  bin="$OUT/bin/$name"
  clog="$OUT/log/$name.compile.log"
  rlog="$OUT/log/$name.run.log"
  if ! TUNGSTEN_INCREMENTAL=0 TUNGSTEN_CLANG_OPT="$OPT -g -fsanitize=undefined" \
       "$COMPILER" compile "$path" --out "$bin" --runtime "$ARCHIVE" --no-lto \
       > "$clog" 2>&1; then
    echo "  FAIL compile $path (see $clog)" >&2
    fail=1
    continue
  fi
  UBSAN_OPTIONS="$UBSAN_ENV" "$bin" > "$rlog" 2>&1
  status=$?
  n="$(grep -c 'runtime error:' "$rlog" || true)"
  if [[ "$n" -gt 0 ]]; then
    echo "  UBSAN $path: $n diagnostic(s) (see $rlog)"
    diag=1
  fi
  if [[ "$status" -ne 0 ]] || grep -Eq '^FAIL([ :]|$)' "$rlog"; then
    echo "  FAIL run $path exited $status (see $rlog)" >&2
    fail=1
  else
    echo "  ok   $path"
  fi
done

# ── 4. UBSan-instrumented compiler compiling a spec ──────────────────────
echo "==> Building UBSan-instrumented compiler and self-exercising it"
ubsan_compiler="$OUT/bin/ubsan-tungsten"
if TUNGSTEN_INCREMENTAL=0 TUNGSTEN_CLANG_OPT="-O0 -g -fsanitize=undefined" \
     "$COMPILER" compile "$ROOT/compiler/tungsten.w" --out "$ubsan_compiler" \
     --runtime "$ARCHIVE" --no-lto > "$OUT/log/ubsan-compiler.compile.log" 2>&1; then
  # Run it from repo root (CWD-relative lexer tables) on a real workload.
  UBSAN_OPTIONS="$UBSAN_ENV" TUNGSTEN_INCREMENTAL=0 \
    TUNGSTEN_CLANG_OPT="$OPT -g -fsanitize=undefined" \
    "$ubsan_compiler" compile spec/numeric/int_spec.w \
    --out "$OUT/bin/probe-int-spec" --runtime "$ARCHIVE" --no-lto \
    > "$OUT/log/ubsan-compiler.run.log" 2>&1
  status=$?
  n="$(grep -c 'runtime error:' "$OUT/log/ubsan-compiler.run.log" || true)"
  [[ "$n" -gt 0 ]] && { echo "  UBSAN compiler workload: $n diagnostic(s) (see $OUT/log/ubsan-compiler.run.log)"; diag=1; }
  if [[ "$status" -ne 0 ]]; then
    echo "  FAIL instrumented compiler exited $status" >&2
    fail=1
  else
    echo "  ok   instrumented compiler compiled spec/numeric/int_spec.w"
  fi
else
  echo "  FAIL building instrumented compiler (see $OUT/log/ubsan-compiler.compile.log)" >&2
  fail=1
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo "==> Summary"
grep -Hn 'runtime error:' "$OUT"/log/*.run.log 2>/dev/null | sort -u -t: -k4 \
  | tee "$OUT/diagnostics.txt"
total="$(wc -l < "$OUT/diagnostics.txt" | tr -d ' ')"
echo "    $total diagnostic line(s); logs in $OUT/log"
[[ "$fail" -eq 0 && "$diag" -eq 0 ]] || exit 1
exit 0
