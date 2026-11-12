#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
REAL_CC="${REAL_CC:-$(command -v clang)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-compile-profiles.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Every pin below is about the flags a PROFILE selects, so an ambient backend
# override must not stand in for them.
unset TUNGSTEN_CLANG_OPT TUNGSTEN_LINK_CACHE

printf '<< "profile probe"\n' >"$TMP/probe.w"
cat >"$TMP/trace-cc" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TRACE_FILE"
exec "$REAL_CC" "$@"
SH
chmod +x "$TMP/trace-cc"

# traced NAME CACHE COMMAND...: run the compiler with a tracing C compiler.
# Every clang invocation lands in $TMP/NAME.trace, one command line per line;
# the last line is the link. Cases that name the same CACHE share its runtime
# archives and bitcode bundles, so the C runtime is compiled once per distinct
# flag set, not once per case. TUNGSTEN_INCREMENTAL=0 turns the binary caches
# off, so every case still runs its own link.
traced() {
  local name="$1" cache="$2"
  shift 2
  : >"$TMP/$name.trace"
  TRACE_FILE="$TMP/$name.trace" REAL_CC="$REAL_CC" \
    TUNGSTEN_CC="$TMP/trace-cc" \
    TUNGSTEN_CACHE_DIR="$TMP/cache-$cache" \
    TUNGSTEN_INCREMENTAL=0 \
    "$COMPILER" "$@" >"$TMP/$name.build"
}

link_of() { tail -n 1 "$TMP/$1.trace"; }

# The clang command that compiled runtime.c in this case, or nothing when the
# case reused a cached archive or bundle.
runtime_compile_of() { grep -E -- ' -c .*/runtime\.c( |$)' "$TMP/$1.trace" || true; }

has() { grep -Eq -- "(^| )$2( |$)" <<<"$1"; }

# expect WHAT LINE [+FLAG | -FLAG | +~REGEX | -~REGEX]...
#   +FLAG   the command line carries FLAG as a whole word
#   -FLAG   it does not
#   +~RE    the command line matches RE anywhere (paths)
#   -~RE    it does not
expect() {
  local what="$1" line="$2" spec
  shift 2
  for spec in "$@"; do
    case "$spec" in
      +~*) grep -Eq -- "${spec#+~}" <<<"$line" ||
             { printf '%s: expected %s in:\n%s\n' "$what" "${spec#+~}" "$line" >&2; exit 1; } ;;
      -~*) ! grep -Eq -- "${spec#-~}" <<<"$line" ||
             { printf '%s: unexpected %s in:\n%s\n' "$what" "${spec#-~}" "$line" >&2; exit 1; } ;;
      +*)  has "$line" "${spec#+}" ||
             { printf '%s: expected %s in:\n%s\n' "$what" "${spec#+}" "$line" >&2; exit 1; } ;;
      -*)  ! has "$line" "${spec#-}" ||
             { printf '%s: unexpected %s in:\n%s\n' "$what" "${spec#-}" "$line" >&2; exit 1; } ;;
    esac
  done
}

no_lto_anywhere() {
  if grep -Eq -- "(^| )$ANY_LTO( |$)" "$TMP/$1.trace"; then
    printf '%s compiled or linked LTO bitcode:\n' "$1" >&2
    cat "$TMP/$1.trace" >&2
    exit 1
  fi
}

no_runtime_compile() {
  if [[ -n "$(runtime_compile_of "$1")" ]]; then
    printf '%s recompiled the runtime instead of reusing %s:\n%s\n' \
      "$1" "$2" "$(runtime_compile_of "$1")" >&2
    exit 1
  fi
}

runs() { [[ "$("$1")" == "profile probe" ]] || { printf '%s did not run\n' "$1" >&2; exit 1; }; }

ANY_LTO='-flto(=[a-z]+)?'
ARCHIVE='/runtime-native-[0-9a-f]+\.a'
BUNDLE='/runtime-lto-[0-9a-f]+/'

# ── Profiles of a single compile ────────────────────────────────────────────
# default: -O3 with symbols, cached native runtime archive, no LTO.
traced default native compile --out "$TMP/default" "$TMP/probe.w"
default_link="$(link_of default)"
expect 'default link' "$default_link" +-O3 +-g --O0 --DNDEBUG "-$ANY_LTO" "+~$ARCHIVE" "-~$BUNDLE"
expect 'default runtime' "$(runtime_compile_of default)" +-O3 +-g "-$ANY_LTO"
runs "$TMP/default"

# --dev: -O0 for the module and its own runtime archive, no LTO.
traced dev native compile --dev --out "$TMP/dev" "$TMP/probe.w"
expect 'dev link' "$(link_of dev)" +-O0 +-g --O3 "-$ANY_LTO" "+~$ARCHIVE" "-~$BUNDLE"
expect 'dev runtime' "$(runtime_compile_of dev)" +-O0 "-$ANY_LTO"
runs "$TMP/dev"

# --release: -O3, no dev checks, and whole-program LTO. The runtime side is a
# cached bitcode bundle compiled with the same -flto=full the link passes: a
# link without the flag would quietly codegen that bitcode without LTO, and
# bitcode without an LTO link is paid for and never used.
#
# The batch goes first, on a cold cache and with two inputs so the links run
# in parallel workers: the parent resolves the bundle once, every link carries
# the flag, and no worker compiles the runtime again.
printf '<< "profile probe"\n' >"$TMP/probe2.w"
traced batch-release lto compile-batch --release "$TMP/probe.w" "$TMP/probe2.w"
batch_release_links="$(grep -E -- '/probe2?\.wc$' "$TMP/batch-release.trace")"
[[ "$(wc -l <<<"$batch_release_links" | tr -d ' ')" == 2 ]] ||
  { printf 'batch --release: expected two links:\n%s\n' "$batch_release_links" >&2; exit 1; }
while IFS= read -r batch_link; do
  expect 'batch --release link' "$batch_link" +-O3 +-DNDEBUG +-flto=full --g "+~$BUNDLE" "-~$ARCHIVE"
done <<<"$batch_release_links"
batch_release_runtime="$(runtime_compile_of batch-release)"
[[ "$(wc -l <<<"$batch_release_runtime" | tr -d ' ')" == 1 ]] ||
  { printf 'batch --release: expected one runtime compile:\n%s\n' "$batch_release_runtime" >&2; exit 1; }
expect 'batch --release runtime' "$batch_release_runtime" +-O3 +-DNDEBUG +-flto=full
runs "$TMP/probe.wc"
runs "$TMP/probe2.wc"

# A single --release compile is the same contract and shares that bundle.
traced release lto compile --release --out "$TMP/release" "$TMP/probe.w"
expect 'release link' "$(link_of release)" +-O3 +-DNDEBUG +-flto=full --g --O0 "+~$BUNDLE" "-~$ARCHIVE"
no_runtime_compile release 'the batch bundle'
runs "$TMP/release"

# --release --no-lto: the release profile on the native archive; no bitcode is
# built anywhere.
traced release-no-lto native compile --release --no-lto --out "$TMP/release-no-lto" "$TMP/probe.w"
expect 'release --no-lto link' "$(link_of release-no-lto)" +-O3 +-DNDEBUG "-$ANY_LTO" "+~$ARCHIVE" "-~$BUNDLE"
no_lto_anywhere release-no-lto
runs "$TMP/release-no-lto"

# --lto outside --release: LTO on the default (checked, symbolized) profile.
traced lto lto compile --lto --out "$TMP/lto" "$TMP/probe.w"
expect '--lto link' "$(link_of lto)" +-O3 +-g +-flto --flto=full "+~$BUNDLE" "-~$ARCHIVE"
expect '--lto runtime' "$(runtime_compile_of lto)" +-O3 +-g +-flto
runs "$TMP/lto"

# --release --fast: fast FP belongs to the emitted module. The runtime bundle
# is the IEEE one --release already built, so nothing is recompiled here.
TUNGSTEN_CLANG_OPT='-O3 -ffast-math' \
  traced release-fast lto compile --release --fast --out "$TMP/release-fast" "$TMP/probe.w"
expect 'release --fast link' "$(link_of release-fast)" +-O3 +-ffast-math +-flto=full "+~$BUNDLE"
no_runtime_compile release-fast 'the release bundle'
runs "$TMP/release-fast"

# Ordinary executables have no dynamic ABI. On macOS, explicitly restrict the
# export trie because the cached native runtime archive contains external C
# symbols; FullLTO can internalize them, but --no-lto cannot. Linux gets the
# same contract by omitting -rdynamic. The JIT host is detected from its call
# to w_jit_load_object and keeps the old export-all behavior.
printf '%s\n' \
  '-> keep_jit_loader(path, name)' \
  '  ccall("w_jit_load_object", path, name)' \
  '<< "jit host probe"' >"$TMP/jit-host.w"
traced jit-host native compile --release --native --fast --no-debug --no-lto \
  --out "$TMP/jit-host" "$TMP/jit-host.w"
jit_host_link="$(link_of jit-host)"

if [[ "$(uname -s)" == "Darwin" ]]; then
  grep -q -- '-Wl,-exported_symbol,_main' <<<"$default_link"
  if grep -q -- '-Wl,-export_dynamic' <<<"$default_link"; then
    printf 'ordinary executable unexpectedly exports its runtime\n' >&2
    exit 1
  fi
  grep -q -- '-Wl,-export_dynamic' <<<"$jit_host_link"
  xcrun dyld_info -exports "$TMP/default" >"$TMP/default.exports"
  xcrun dyld_info -exports "$TMP/jit-host" >"$TMP/jit-host.exports"
  if grep -Eq '[[:space:]]_w_add$' "$TMP/default.exports"; then
    printf 'ordinary executable export trie contains w_add\n' >&2
    exit 1
  fi
  grep -Eq '[[:space:]]_w_add$' "$TMP/jit-host.exports"
else
  if grep -Eq '(^| )-rdynamic( |$)' <<<"$default_link"; then
    printf 'ordinary executable unexpectedly uses -rdynamic\n' >&2
    exit 1
  fi
  grep -Eq '(^| )-rdynamic( |$)' <<<"$jit_host_link"
  nm -D --defined-only "$TMP/default" >"$TMP/default.exports"
  nm -D --defined-only "$TMP/jit-host" >"$TMP/jit-host.exports"
  if grep -Eq '[[:space:]]w_add$' "$TMP/default.exports"; then
    printf 'ordinary executable dynamic table contains w_add\n' >&2
    exit 1
  fi
  grep -Eq '[[:space:]]w_add$' "$TMP/jit-host.exports"
fi
[[ "$("$TMP/jit-host")" == "jit host probe" ]]

# ── compile-batch ───────────────────────────────────────────────────────────
# `compile-batch` has its own positional-file pass. Keep --dev out of that file
# list and prove the batch linker selects the same explicit O0 profile.
rm -f "$TMP/probe.wc"
traced batch-dev native compile-batch --dev --no-lto "$TMP/probe.w"
expect 'batch --dev link' "$(link_of batch-dev)" +-O0 --O3 "-$ANY_LTO" "+~$ARCHIVE"
[[ -x "$TMP/probe.wc" ]]
runs "$TMP/probe.wc"

# --no-lto on a release batch: native archive, and no bitcode is compiled.
rm -f "$TMP/probe.wc"
traced batch-release-no-lto native compile-batch --release --no-lto "$TMP/probe.w"
expect 'batch --release --no-lto link' "$(link_of batch-release-no-lto)" +-O3 +-DNDEBUG "-$ANY_LTO" "+~$ARCHIVE"
no_lto_anywhere batch-release-no-lto
runs "$TMP/probe.wc"

if "$COMPILER" compile --dev --release --out "$TMP/conflict" "$TMP/probe.w" \
    >"$TMP/conflict.out" 2>&1; then
  printf 'compile accepted mutually exclusive --dev and --release\n' >&2
  exit 1
fi
grep -q -- '--dev and --release are mutually exclusive' "$TMP/conflict.out"

printf 'compile profile contracts: PASS\n'
