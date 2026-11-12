#!/usr/bin/env bash
# A compiler image learns its kind from TUNGSTEN_COMPILER_IMAGE, which
# delegate_compiler_image (compiler/lib/driver/link.w) sets when it execs the
# image. The mark describes that one process: the image reads it and takes it
# out of its environment, so the programs it runs start clean. When it
# leaked, a script run by the interpreter image that started
# `tungsten run --interpret` did not delegate to the interpreter image and
# died with "undefined method 'new' for nil" (and a program run by the Metal
# image passed the mark to any compile it started).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
IMAGES="$ROOT/build/compiler-images"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-image-env.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if [ ! -x "$IMAGES/tungsten-repl" ]; then
  printf 'skip: no interpreter image at %s (run bin/tungsten build)\n' "$IMAGES/tungsten-repl"
  exit 0
fi

cat >"$TMP/child.w" <<'W'
<< "child ran, mark " + (env("TUNGSTEN_COMPILER_IMAGE") == nil ? "unset" : env("TUNGSTEN_COMPILER_IMAGE"))
W
cat >"$TMP/parent.w" <<'W'
<< "parent mark " + (env("TUNGSTEN_COMPILER_IMAGE") == nil ? "unset" : env("TUNGSTEN_COMPILER_IMAGE"))
ok = system("'" + env("IMAGE_ENV_LAUNCHER") + "' run --interpret child.w")
<< "child status " + (ok ? "ok" : "failed")
W

# 1. An interpreted program (run by the interpreter image) starts another
#    interpreted program.
(cd "$TMP" && IMAGE_ENV_LAUNCHER="$TUNGSTEN" "$TUNGSTEN" run --interpret parent.w) >"$TMP/interp.out" 2>&1 ||
  fail "interpreted parent failed: $(cat "$TMP/interp.out")"
grep -qx 'parent mark unset' "$TMP/interp.out" || fail "the interpreter image left its mark for the program: $(cat "$TMP/interp.out")"
grep -qx 'child ran, mark unset' "$TMP/interp.out" || fail "the nested run --interpret did not run: $(cat "$TMP/interp.out")"
grep -qx 'child status ok' "$TMP/interp.out" || fail "the nested run --interpret failed: $(cat "$TMP/interp.out")"
printf 'ok   interpreted program starts run --interpret (mark not inherited)\n'

# 2. A compiled program run by the Metal image, exec'd the way the compiler
#    delegates to it.
if [ -x "$IMAGES/tungsten-metal" ]; then
  (cd "$TMP" && env TUNGSTEN_ROOT="$ROOT" TUNGSTEN_COMPILER_IMAGE=metal TUNGSTEN_CACHE_DIR="$TMP/cache" \
     "$IMAGES/tungsten-metal" run child.w) >"$TMP/metal.out" 2>&1 ||
    fail "the Metal image could not run a program: $(cat "$TMP/metal.out")"
  grep -qx 'child ran, mark unset' "$TMP/metal.out" || fail "the Metal image left its mark for the program: $(cat "$TMP/metal.out")"
  printf 'ok   program run by the Metal image does not inherit the mark\n'
fi
