#!/usr/bin/env bash
# A Bitfile `app` line embeds an Info.plist in the executable it names (the
# Mach-O __TEXT,__info_plist section), so the bare bin/<exe> shows the app's
# name in the menu bar as bin/<Name>.app does. Checks:
#   - the compiler's --info-plist embeds the file, a changed plist relinks
#     through the link-artifact cache, and a missing file is an error;
#   - `tungsten build` of a bit embeds CFBundleName for its app's executable,
#     skips an unchanged rebuild, relinks when the app's name changes, and
#     embeds nothing for an executable no app line names.
# Hermetic: the build store and compile cache live under a temp directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${TUNGSTEN_COMPILER:-$ROOT/bin/tungsten-compiler}"

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'app info plist: SKIP (macOS only)\n'
  exit 0
fi
if [ ! -x "$COMPILER" ]; then
  printf 'app info plist: SKIP (no compiler)\n'
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-app-plist.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT INT TERM
export TUNGSTEN_BUILD_STORE="$TMP/store"
unset TUNGSTEN_CACHE_DIR

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

has_section() {
  otool -l "$1" | grep -q 'sectname __info_plist'
}

# CFBundleName of the plist embedded in executable $1 ("" when there is none)
embedded_name() {
  rm -f "$TMP/extracted.plist"
  has_section "$1" || return 0
  segedit "$1" -extract __TEXT __info_plist "$TMP/extracted.plist" >/dev/null 2>&1 || return 0
  plutil -extract CFBundleName raw "$TMP/extracted.plist" 2>/dev/null || true
}

write_plist() {
  cat >"$2" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$1</string>
</dict>
</plist>
PLIST
}

# ── 1. The compiler's --info-plist ──────────────────────────────
WORK="$TMP/work"
mkdir -p "$WORK"
printf '<< "hello"\n' >"$WORK/main.w"
write_plist Alpha "$WORK/info.plist"
compile() {
  (cd "$WORK" && TUNGSTEN_CACHE_DIR="$TMP/cc" TUNGSTEN_ROOT="$ROOT" TUNGSTEN_INCREMENTAL=0 TUNGSTEN_LINK_CACHE=1 \
    "$COMPILER" compile "$WORK/main.w" --out "$@")
}
compile "$WORK/a" --info-plist info.plist >/dev/null
[ "$("$WORK/a")" = "hello" ] || fail "the program with an embedded plist does not run"
[ "$(embedded_name "$WORK/a")" = "Alpha" ] || fail "--info-plist did not embed the plist"
# the same IR and a changed plist: the link cache must not hand back the old executable
write_plist Beta "$WORK/info.plist"
compile "$WORK/b" --info-plist info.plist >/dev/null
[ "$(embedded_name "$WORK/b")" = "Beta" ] || fail "a changed plist was served from the link cache"
compile "$WORK/c" >/dev/null
has_section "$WORK/c" && fail "a program compiled without --info-plist has a plist section"
if compile "$WORK/d" --info-plist "$WORK/missing.plist" >/dev/null 2>&1; then
  fail "a missing --info-plist file is not an error"
fi

# ── 2. `tungsten build` of a bit with an app line ───────────────
PKG="$TMP/demo"
mkdir -p "$PKG/lib"
printf '<< "demo"\n' >"$PKG/lib/main.w"
printf '<< "tool"\n' >"$PKG/lib/tool.w"
bitfile() {
  {
    printf 'name "demo"\n'
    printf 'executable "demo", source: "lib/main.w"\n'
    printf 'executable "tool", source: "lib/tool.w"\n'
    [ -z "$1" ] || printf 'app "%s", executable: "demo", id: "test.tungsten.demo", version: "1.2"\n' "$1"
  } >"$PKG/Bitfile"
}
build() {
  local log
  if ! log="$(cd "$PKG" && "$ROOT/bin/tungsten" build 2>&1)"; then
    printf '%s\n' "$log" >&2
    fail "tungsten build failed"
  fi
  printf '%s\n' "$log"
}

bitfile "Demo One"
out="$(build)"
[ "$("$PKG/bin/demo")" = "demo" ] || fail "bin/demo does not run: $out"
[ "$(embedded_name "$PKG/bin/demo")" = "Demo One" ] || fail "bin/demo does not embed its app's CFBundleName"
plutil -lint -s "$TMP/extracted.plist" || fail "the embedded plist does not lint"
[ "$(plutil -extract CFBundleIdentifier raw "$TMP/extracted.plist")" = "test.tungsten.demo" ] || fail "embedded CFBundleIdentifier"
[ "$(plutil -extract CFBundleVersion raw "$TMP/extracted.plist")" = "1.2" ] ||
  fail "the embedded CFBundleVersion is not the version (it must not be the build time: it keys the store)"
has_section "$PKG/bin/tool" && fail "an executable no app line names has a plist section"
[ "$(embedded_name "$PKG/bin/Demo One.app/Contents/MacOS/demo")" = "Demo One" ] || fail "the bundle's executable lost the plist"
[ -f "$PKG/bin/Demo One.app/Contents/Info.plist" ] || fail "the bundle has no Info.plist"

out="$(build)"
printf '%s\n' "$out" | grep 'skip' | grep -q '/bin/demo$' || fail "an unchanged rebuild was not skipped: $out"

bitfile "Demo Two"
out="$(build)"
[ "$(embedded_name "$PKG/bin/demo")" = "Demo Two" ] || fail "renaming the app did not relink bin/demo: $out"

# back to the first name: the store's entry for it, with its plist
bitfile "Demo One"
build >/dev/null
[ "$(embedded_name "$PKG/bin/demo")" = "Demo One" ] || fail "the store served the wrong plist"

bitfile ""
out="$(build)"
has_section "$PKG/bin/demo" && fail "bin/demo keeps a plist section after its app line is removed: $out"
[ "$("$PKG/bin/demo")" = "demo" ] || fail "bin/demo without an app does not run"

printf 'app info plist: PASS\n'
