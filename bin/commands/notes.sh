#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Tungsten Notes requires macOS.' >&2; exit 1; }
APP="${TUNGSTEN_NOTES_APP:-$ROOT/build/apps/Tungsten Notes.app}"
MODE=open
DOCUMENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only) MODE=build ;;
    --validate) MODE=validate ;;
    --help|-h) echo 'Usage: tungsten notes [--build-only | --validate] [document.tnotes]'; exit 0 ;;
    -*) echo "Unknown Notes option: $1" >&2; exit 1 ;;
    *) [[ -z "$DOCUMENT" ]] || { echo 'Pass one document.' >&2; exit 1; }; DOCUMENT="$1" ;;
  esac
  shift
done
if [[ -z "${TUNGSTEN_NOTES_APP:-}" ]]; then
  BINARY="$APP/Contents/MacOS/TungstenNotes"
  if [[ ! -x "$BINARY" || "$ROOT/apps/tungsten-notes/Notes.swift" -nt "$BINARY" || "$ROOT/apps/tungsten-notes/Info.plist" -nt "$BINARY" ]]; then
    mkdir -p "$APP/Contents/MacOS"
    swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx14.0" \
      "$ROOT/apps/tungsten-notes/Notes.swift" -o "$BINARY.new"
    mv "$BINARY.new" "$BINARY"
    cp "$ROOT/apps/tungsten-notes/Info.plist" "$APP/Contents/Info.plist"
    codesign --force --sign - "$APP" >/dev/null 2>&1
  fi
fi
[[ -d "$APP" ]] || { echo "Notes app not found: $APP" >&2; exit 1; }
if [[ "$MODE" == build ]]; then echo "$APP"; exit 0; fi
if [[ -n "$DOCUMENT" && ! -f "$DOCUMENT" ]]; then echo "Document not found: $DOCUMENT" >&2; exit 1; fi
if [[ "$MODE" == validate ]]; then
  [[ -n "$DOCUMENT" ]] || { echo '--validate needs a document.' >&2; exit 1; }
  exec "$APP/Contents/MacOS/TungstenNotes" --validate "$DOCUMENT"
fi
if [[ -n "$DOCUMENT" ]]; then exec open -a "$APP" "$DOCUMENT"; fi
exec open -a "$APP"
