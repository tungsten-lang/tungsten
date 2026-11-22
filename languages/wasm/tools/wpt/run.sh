#!/bin/sh
# Run WPT wasm/jsapi tests with Blade's JS engine: run.sh WPT_DIR JSTEST_BINARY [test.any.js ...]
# Each test gets testharness.js, the prelude/reporter here, and its META: script= files.
WPT="$1"; BIN="$2"; shift 2
HERE="$(cd "$(dirname "$0")" && pwd)"
for t in "$@"; do
  metas=""
  for m in $(grep '^// META: script=' "$t" | sed 's/.*script=//'); do
    case "$m" in /*) metas="$metas $WPT$m" ;; *) metas="$metas $(dirname "$t")/$m" ;; esac
  done
  out=$(timeout 120 "$BIN" "$HERE/prelude.js" "$WPT/resources/testharness.js" "$HERE/report.js" $metas "$t" "$HERE/done.js" 2>&1)
  line=$(echo "$out" | grep '^WPT ' | tail -1)
  [ -z "$line" ] && line="WPT 0/0 (no result: $(echo "$out" | tail -1 | cut -c1-100))"
  echo "${t#$WPT/}: $line"
  [ -n "$VERBOSE" ] && echo "$out" | grep -v '^WPT '
done
