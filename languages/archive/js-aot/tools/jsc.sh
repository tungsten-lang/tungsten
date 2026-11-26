#!/bin/sh
# jsc.sh file.js -o out [--release] — JavaScript to a native binary (tools/jsc.w).
# Builds build/jsc on first use (or when JSC_REBUILD=1).
set -e
D="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
JSC="$D/build/jsc"
if [ ! -x "$JSC" ] || [ "$JSC_REBUILD" = "1" ]; then
  mkdir -p "$D/build"
  "$ROOT/bin/tungsten" -o "$JSC" "$D/tools/jsc.w" >&2
fi
js="$1"; shift
case "$js" in /*) ;; *) js="$PWD/$js" ;; esac
# the translated script differs per call: never reuse an incremental binary
TUNGSTEN_ROOT="$ROOT" TUNGSTEN_INCREMENTAL=0 JSC_JS="$js" exec "$JSC" compile "$D/runtime/main.w" "$@"
