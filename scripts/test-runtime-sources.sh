#!/usr/bin/env bash
# runtime/sources.txt is the one list of runtime translation units. This pins:
#   1. every runtime source is in it (and every listed file exists), so a new
#      runtime file cannot be forgotten by one build path;
#   2. its shell reader, runtime/sources.sh, selects the documented sets;
#   3. no build path keeps a hand-written list beside it;
#   4. the compiler's own reader (compiler/lib/driver/link.w) selects what the
#      shell reader selects: the runtime archive and a companion are compiled
#      from exactly the manifest's files (traced through TUNGSTEN_CC);
#   5. when this checkout has built its compiler, the compiler's runtime
#      archive (bin/commands/build.w) holds exactly the manifest's set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"
SOURCES="$ROOT/runtime/sources.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-runtime-sources.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok   %s\n' "$*"; }
sel() { sh "$SOURCES" "$@" | tr '\n' ' ' | sed 's/ $//'; }

case "$(uname -s)" in
  Darwin) HOST=darwin ;;
  Linux) HOST=linux ;;
  *) HOST="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac

# 1. coverage, both ways.
listed="$TMP/listed"
awk '!/^[ \t]*#/ && NF >= 3 { print $1 }' "$ROOT/runtime/sources.txt" | LC_ALL=C sort -u >"$listed"
(cd "$ROOT/runtime" && find . -path ./tests -prune -o -type f \( -name '*.c' -o -name '*.m' \) -print) |
  sed 's|^\./||' | grep -Ev '^(bench_|test_)' | LC_ALL=C sort -u >"$TMP/tree"
missing="$(comm -23 "$TMP/tree" "$listed" | tr '\n' ' ')"
[ -z "$missing" ] || fail "runtime sources missing from runtime/sources.txt: $missing"
stale="$(comm -13 "$TMP/tree" "$listed" | tr '\n' ' ')"
[ -z "$stale" ] || fail "runtime/sources.txt lists files that do not exist: $stale"
pass "every runtime source is listed and every listed file exists ($(wc -l <"$listed" | tr -d ' ') files)"

# 2. the shell reader.
expect() {
  local want="$1"; shift
  local got
  got="$(sel "$@")"
  [ "$got" = "$want" ] || fail "sources.sh $*: expected '$want', got '$got'"
}
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c terminal_input.c aks.c event_kqueue.c tls_stub.c" darwin program event tls-stub
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c terminal_input.c aks.c event_epoll.c tls.c slab_zstd.c" linux program event tls zstd
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c terminal_input.c aks.c event_iouring.c tls_stub.c" linux program event-iouring tls-stub
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c terminal_input.c aks.c event_kqueue.c tls_stub.c slab_zstd.c ssmr_witness.c lexchar_tables.c unicode_tables.c metal.m hid_bridge.m blas_bridge.c" \
  darwin compiler event tls-stub zstd
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c terminal_input.c aks.c event_epoll.c tls_stub.c slab_zstd_stub.c http2.c ssmr_witness.c lexchar_tables.c unicode_tables.c" \
  linux compiler event tls-stub zstd-stub http2
expect "runtime.c runtime_crypto.c runtime_gmp.c runtime_http.c runtime_udp.c aks.c tls_stub.c slab_zstd_stub.c ssmr_witness.c lexchar_tables.c unicode_tables.c tensor_bridge.c" wasm wasm
expect "metal.m graphics.m hid_bridge.m" darwin companion:bridges
expect "" linux companion:bridges
expect "openblas_bridge.c" linux companion:blas
expect "media/media.c media/media_avf.m media/media_sysdec.m" darwin companion:media
expect "credentials.m" darwin companion:credentials
expect "" linux companion:credentials
[ "$(sh "$SOURCES" -f darwin companion:blas)" = "$(printf 'blas_bridge.c\t-fno-finite-math-only')" ] ||
  fail "sources.sh -f does not carry blas_bridge.c's extra cflags"
if sh "$SOURCES" darwin >/dev/null 2>&1; then fail "sources.sh without a set must fail"; fi
pass "runtime/sources.sh selects the documented sets"

# 3. no second list. The event backends are named by the manifest alone; a
#    build path that spells one out has grown its own list again.
for f in compiler/lib/driver/link.w compiler/lib/driver/pipeline.w compiler/lib/driver/ir.w \
         bin/commands/build.w bin/commands/bootstrap.sh bin/commands/compile.rb bin/commands/forge.rb \
         runtime/Makefile wasm/scripts/compile_runtime.sh scripts/ubsan_runtime_sweep.sh; do
  if grep -n 'event_kqueue\.c\|event_epoll\.c\|tls_stub\.c\|"terminal_input\.c"' "$ROOT/$f" >"$TMP/hits"; then
    fail "$f names runtime sources itself: $(head -1 "$TMP/hits")"
  fi
done
pass "no build path keeps its own runtime source list"

# 4. the compiler's reader. The traced C compiler refuses every runtime
#    compile (cheap), so the driver tries the archive, then a companion
#    object, then the from-source link, and each attempt is logged.
if [ ! -x "$COMPILER" ]; then
  printf 'skip compiler checks: no %s\n' "$COMPILER"
  exit 0
fi
REAL_CC="$(command -v clang)"
cat >"$TMP/trace-cc" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TRACE_FILE"
case " $* " in
  *"/runtime/"*) exit 1 ;;
esac
exec "$REAL_CC" "$@"
SH
chmod +x "$TMP/trace-cc"
printf '<< 7.prime?\n' >"$TMP/prime.w"
(
  cd "$TMP"
  unset TLS TUNGSTEN_TLS USE_IOURING TUNGSTEN_CLANG_OPT
  TRACE_FILE="$TMP/prime.trace" REAL_CC="$REAL_CC" TUNGSTEN_CC="$TMP/trace-cc" \
    TUNGSTEN_CACHE_DIR="$TMP/cache" TUNGSTEN_INCREMENTAL=0 TUNGSTEN_ROOT="$ROOT" \
    "$COMPILER" compile prime.w --out prime --dev >"$TMP/prime.build" 2>&1
) && fail "the traced compile should have failed (it refuses runtime compiles)"
runtime_files() {
  # the runtime/ sources on one traced command line, relative, in order
  tr ' ' '\n' | tr -d "'" | sed -n 's|.*/runtime//*||p' | grep -E '\.(c|m)$' | tr '\n' ' ' | sed 's/ $//'
}
sorted_words() {
  tr ' ' '\n' | grep -v '^$' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
archive_cmds="$(grep -- ' -c ' "$TMP/prime.trace" | grep -v '/companion-' || true)"
[ -n "$archive_cmds" ] || fail "no runtime archive compile in the trace: $(cat "$TMP/prime.trace" | head -5)"
want="$(sel "$HOST" program event tls-stub | sorted_words)"
got="$(printf '%s\n' "$archive_cmds" | runtime_files | sorted_words)"
[ "$got" = "$want" ] || fail "runtime archive compiles '$got', the manifest says '$want'"
companion_cmd="$(grep -- ' -c ' "$TMP/prime.trace" | grep 'ssmr_witness\.c' | head -1 || true)"
[ -n "$companion_cmd" ] || fail "no companion compile for 7.prime? in the trace"
got="$(printf '%s\n' "$companion_cmd" | runtime_files)"
[ "$got" = "$(sel "$HOST" companion:prime)" ] || fail "prime companion compiles '$got'"
# The from-source link: the program set, then each companion the driver
# tried to compile on its own (in that order; 7.prime? needs the prime
# companion and whatever else its IR references).
companions="$(grep -- ' -c ' "$TMP/prime.trace" | grep '/companion-' | runtime_files | tr '\n' ' ' | sed 's/ $//')"
link_cmd="$(tail -n 1 "$TMP/prime.trace")"
got="$(printf '%s\n' "$link_cmd" | runtime_files)"
want="$(sel "$HOST" program event tls-stub) $companions"
[ "$got" = "$want" ] || fail "from-source link compiles '$got', expected '$want'"
pass "the compiler compiles the runtime archive, a companion and a from-source link from the manifest"

# 5. the compiler's own runtime archive, as the last build of this checkout
#    recorded it.
current="$ROOT/build/runtime-current.manifest"
archive=""
[ -f "$current" ] && archive="$(head -n 1 "$current")"
if [ -z "$archive" ] || [ ! -f "$archive" ]; then
  printf 'skip compiler runtime archive check: no recorded archive (run bin/tungsten build)\n'
  exit 0
fi
members="$(ar t "$archive" | grep '\.o$' | grep -v 'slab_zstd' | LC_ALL=C sort | tr '\n' ' ')"
want="$(sh "$SOURCES" "$HOST" compiler event tls-stub | grep -v slab_zstd | sed 's|.*/||; s/\.[cm]$/.o/' | LC_ALL=C sort | tr '\n' ' ')"
[ "$members" = "$want" ] || fail "compiler runtime archive holds '$members', the manifest says '$want'"
zstd_members="$(ar t "$archive" | grep -c 'slab_zstd' || true)"
[ "$zstd_members" = 1 ] || fail "compiler runtime archive should hold exactly one slab_zstd object, has $zstd_members"
pass "the compiler's runtime archive ($archive) holds the manifest's compiler set"
