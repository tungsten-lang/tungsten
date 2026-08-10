#!/usr/bin/env bash
#
# test-fast-parse-parity.sh — the gate for TUNGSTEN_C_FAST_PARSE.
#
# Proves (or disproves) that the C VM's fast loader (parse_ast.c, enabled by
# TUNGSTEN_C_FAST_PARSE=1) and the canonical Tungsten parser produce
# byte-identical stage-1 compiler IR. It emits stage-1 .ll twice with the
# same scratch C VM — once with TUNGSTEN_C_FAST_PARSE=1, once with =0 — and
# byte-compares the outputs. If they match, it acid-tests the fast-built
# stage-1 compiler by compiling and running a program that exercises the
# bignum pow path ((2 ** 100).to_s) and a `## i64` shift.
#
# Why not `--ast`? Comparing `--ast` dumps is vacuous for this purpose: the
# --ast path always goes through the canonical parser, so it can never
# observe a fast-parse divergence. Only the emitted stage-1 .ll — produced
# by a compiler whose own source was loaded through the fast path — is a
# real oracle.
#
# This script is the gate for flipping TUNGSTEN_C_FAST_PARSE back to 1 in
# bin/commands/bootstrap.sh: do not flip the default until this passes.
#
# Exit codes: 0 = parity + acid test pass; 1 = divergence or build/compile
# failure; 2 = missing prerequisite (run `bin/tungsten build --no-bits`).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UNAME_S="$(uname -s)"

# ── Scratch area ────────────────────────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-fast-parse-parity.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ── 1. Scratch C VM (kept in build/parity-check for reuse) ──────
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
case "$CORES" in ''|*[!0-9]*) CORES=4 ;; esac
JOBS="$CORES"
if [ "$JOBS" -gt 8 ]; then JOBS=8; fi
if [ "$JOBS" -lt 1 ]; then JOBS=1; fi

printf '==> Building scratch C VM (make -C implementations/c BUILD_DIR=build/parity-check -j%s)\n' "$JOBS"
if ! make -C "$ROOT/implementations/c" BUILD_DIR=build/parity-check -j"$JOBS" \
    >"$WORK/vm-make.log" 2>&1; then
  tail -n 40 "$WORK/vm-make.log" >&2
  printf 'FAIL: could not build the C VM (see above)\n' >&2
  exit 1
fi
VM="$ROOT/implementations/c/build/parity-check/tungsten-c"
[ -x "$VM" ] || { printf 'FAIL: C VM missing at %s\n' "$VM" >&2; exit 1; }

# ── 2. Runtime archive from the current build manifest ──────────
MANIFEST="$ROOT/build/cache/runtime-current.manifest"
if [ ! -f "$MANIFEST" ]; then
  printf 'ERROR: %s not found.\n' "$MANIFEST" >&2
  printf 'Run `bin/tungsten build --no-bits` first to produce a runtime archive.\n' >&2
  exit 2
fi
ARCHIVE="$ROOT/build/cache/$(head -n 1 "$MANIFEST")"
if [ ! -f "$ARCHIVE" ]; then
  printf 'ERROR: runtime archive %s (from %s) is missing.\n' "$ARCHIVE" "$MANIFEST" >&2
  printf 'Run `bin/tungsten build --no-bits` first to rebuild it.\n' >&2
  exit 2
fi

# The env manifest (manifest line 2) records the zstd/onig flags the archive
# was compiled with; exporting them keeps the stage-1 link consistent with
# the archive and skips the compiler's own pkg-config probes ("set even to
# empty" means resolved — see compiler/tungsten.w).
ENV_MANIFEST="$ROOT/build/cache/$(sed -n '2p' "$MANIFEST")"
if [ -f "$ENV_MANIFEST" ]; then
  export TUNGSTEN_ZSTD_CFLAGS="$(sed -n '2p' "$ENV_MANIFEST")"
  export TUNGSTEN_ZSTD_LDFLAGS="$(sed -n '3p' "$ENV_MANIFEST")"
  export TUNGSTEN_ONIG_CFLAGS="$(sed -n '4p' "$ENV_MANIFEST")"
  export TUNGSTEN_ONIG_LDFLAGS="$(sed -n '5p' "$ENV_MANIFEST")"
fi

# ── 3. Environment (mirrors bin/commands/bootstrap.sh) ──────────
export TUNGSTEN_ROOT="$ROOT"
export BIT_HOME="$ROOT/bits"
export TUNGSTEN_LEX64_TABLE="$ROOT/languages/tungsten/tungsten.lex64"
export TUNGSTEN_CLANG_OPT="-O0"

# TUNGSTEN_MARCH_ARGS: same derivation as bootstrap.sh — load TUNGSTEN_CPU /
# TUNGSTEN_CC from ~/.tungsten/config, then map cpu -> compiler flags.
. "$ROOT/bin/commands/config.sh"
tungsten_load_build_config

normalize_cpu() {
  case "$1" in
    v1|v2|v3|v4) printf 'x86-64-%s' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}
HOST_CPU="$(normalize_cpu "${TUNGSTEN_CPU:-native}")"
case "$HOST_CPU" in
  ''|*[!A-Za-z0-9_.+-]*) printf 'FAIL: invalid CPU name: %s\n' "$HOST_CPU" >&2; exit 1 ;;
esac
case "$HOST_CPU" in
  x86-64-v1|x86-64-v2|x86-64-v3|x86-64-v4)
    TUNGSTEN_MARCH_ARGS="-march=$HOST_CPU -mtune=generic"
    ;;
  native)
    case "$(uname -m)" in
      x86_64|amd64) TUNGSTEN_MARCH_ARGS="-march=native -mtune=native" ;;
      *) TUNGSTEN_MARCH_ARGS="-mcpu=native" ;;
    esac
    ;;
  *) TUNGSTEN_MARCH_ARGS="-mcpu=$HOST_CPU" ;;
esac
export TUNGSTEN_MARCH_ARGS

printf '    VM:       %s\n' "$VM"
printf '    runtime:  %s\n' "$ARCHIVE"
printf '    cpu:      %s (TUNGSTEN_MARCH_ARGS=%s)\n' "$HOST_CPU" "$TUNGSTEN_MARCH_ARGS"

# ── 4. Emit stage-1 .ll twice: fast parse vs canonical ──────────
emit_stage1() {
  # $1 = TUNGSTEN_C_FAST_PARSE value, $2 = label
  local fast="$1" label="$2"
  local out="$WORK/stage1-$label" log="$WORK/stage1-$label.log"
  printf '==> Stage 1 (%s parser, TUNGSTEN_C_FAST_PARSE=%s)\n' "$label" "$fast"
  if ! TUNGSTEN_C_FAST_PARSE="$fast" TUNGSTEN_LL_PATH="$out.ll" \
      "$VM" "$ROOT/compiler/tungsten.w" compile "$ROOT/compiler/tungsten.w" \
        --out "$out" --runtime "$ARCHIVE" --no-lto \
        >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    printf 'FAIL: stage-1 compile (%s parser) failed — full log: %s\n' \
      "$label" "$log" >&2
    # The trap would delete the log with $WORK; keep a copy for debugging.
    cp "$log" "/tmp/tungsten-fast-parse-parity-$label.log" 2>/dev/null || true
    printf '      (log preserved at /tmp/tungsten-fast-parse-parity-%s.log)\n' \
      "$label" >&2
    exit 1
  fi
  if [ ! -f "$out.ll" ]; then
    printf 'FAIL: stage-1 (%s parser) produced no .ll at %s\n' "$label" "$out.ll" >&2
    exit 1
  fi
}

emit_stage1 1 fast
emit_stage1 0 canonical

FAST_LL="$WORK/stage1-fast.ll"
CANON_LL="$WORK/stage1-canonical.ll"

# ── 5. Byte-compare ─────────────────────────────────────────────
normalize() {
  sed 's/%t[0-9]*/%T/g; s/@__wy_[a-f0-9]*/@FN/g; s/cs\.[0-9]*/CS/g; s/@.ic, i64 [0-9]*/@IC/g; s/@.str.[0-9]*/@STR/g; s/@.wfm.[0-9]*/@WFM/g; s/\[[0-9]* x/[N x/g' "$1"
}

if cmp -s "$FAST_LL" "$CANON_LL"; then
  printf 'PASS: stage-1 IR byte-identical (fast == canonical)\n'
else
  # diff exits 1 when files differ; keep it out of pipelines (pipefail+set -e).
  diff "$FAST_LL" "$CANON_LL" > "$WORK/raw.diff" || true
  raw_diff_lines="$(wc -l < "$WORK/raw.diff" | tr -d ' ')"
  fast_calls="$(grep -c w_method_call_cached "$FAST_LL" || true)"
  canon_calls="$(grep -c w_method_call_cached "$CANON_LL" || true)"
  printf 'FAIL: stage-1 IR diverges (fast != canonical)\n'
  printf '    raw diff lines:               %s\n' "$raw_diff_lines"
  printf '    w_method_call_cached (fast):  %s\n' "$fast_calls"
  printf '    w_method_call_cached (canon): %s\n' "$canon_calls"
  normalize "$FAST_LL"  > "$WORK/fast.norm.ll"
  normalize "$CANON_LL" > "$WORK/canonical.norm.ll"
  diff "$WORK/fast.norm.ll" "$WORK/canonical.norm.ll" > "$WORK/norm.diff" || true
  norm_diff_lines="$(wc -l < "$WORK/norm.diff" | tr -d ' ')"
  printf '    normalized diff lines:        %s\n' "$norm_diff_lines"
  printf '    first 3 divergent hunks (normalized; < = fast, > = canonical):\n'
  # Truncate pathological lines (the static string slab is one multi-hundred-KB
  # constant line) so a divergence report stays readable in a terminal.
  awk '/^[0-9]/ { h++ } h > 3 { exit } {
    line = "      " $0
    if (length(line) > 220) line = substr(line, 1, 220) " ...[line truncated]"
    print line
  }' "$WORK/norm.diff"
  exit 1
fi

# ── 6. Acid test: the fast-built stage-1 compiler must work ─────
printf '==> Acid test: compile+run a program with the fast-built stage 1\n'
FAST_BIN="$WORK/stage1-fast"
if [ "$UNAME_S" = Darwin ]; then
  codesign --force -s - "$FAST_BIN" >/dev/null 2>&1 \
    || { printf 'FAIL: could not ad-hoc sign %s\n' "$FAST_BIN" >&2; exit 1; }
fi

cat > "$WORK/acid.w" <<'EOF'
<< (2 ** 100).to_s
n = 1 ## i64
s = n << 40
<< s
EOF

if ! "$FAST_BIN" compile "$WORK/acid.w" --out "$WORK/acid" \
    --runtime "$ARCHIVE" --no-lto >"$WORK/acid-compile.log" 2>&1; then
  tail -n 40 "$WORK/acid-compile.log" >&2
  printf 'FAIL: fast-built stage 1 could not compile the acid program\n' >&2
  exit 1
fi
if [ "$UNAME_S" = Darwin ]; then
  codesign --force -s - "$WORK/acid" >/dev/null 2>&1 || true
fi

printf '1267650600228229401496703205376\n1099511627776\n' > "$WORK/acid.expected"
if ! "$WORK/acid" > "$WORK/acid.out" 2>&1; then
  cat "$WORK/acid.out" >&2
  printf 'FAIL: acid program crashed\n' >&2
  exit 1
fi
if cmp -s "$WORK/acid.out" "$WORK/acid.expected"; then
  printf 'PASS: fast-built stage 1 compiles and runs programs correctly\n'
  printf '      (2 ** 100).to_s = 1267650600228229401496703205376; 1 ## i64 << 40 = 1099511627776\n'
else
  printf 'FAIL: acid program output mismatch\n' >&2
  printf '--- expected\n' >&2
  cat "$WORK/acid.expected" >&2
  printf '--- got\n' >&2
  cat "$WORK/acid.out" >&2
  exit 1
fi

exit 0
