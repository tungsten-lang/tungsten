#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALLER_PWD="$PWD"
CACHE_ROOT="${TUNGSTEN_CACHE_DIR:-$ROOT/build/cache}/debug"
DEBUGGER=auto
BUILD_ONLY=0
RUN_DIRECT=0
OUTPUT=""
SOURCE=""
PROGRAM_ARGS=()

usage() {
  cat <<'EOF'
Usage: tungsten debug [options] FILE.w [-- PROGRAM_ARGS...]

Build FILE with symbols, frame pointers, development checks, and a validated
sidemap, then launch LLDB on macOS or GDB elsewhere. Artifacts default to
build/cache/debug/runs/.

Options:
  --debugger NAME  auto, lldb, or gdb (default: auto)
  --build-only     build and validate artifacts without launching a debugger
  --run            run the debug binary directly and preserve its exit status
  --output PATH    explicit debug binary path
  --cache-dir PATH debug artifact root (default: build/cache/debug)
  -h, --help       show this help
EOF
}

die() {
  echo "tungsten debug: $*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --debugger) shift; [[ "$#" -gt 0 ]] || die "--debugger needs a value"; DEBUGGER="$1" ;;
    --debugger=*) DEBUGGER="${1#--debugger=}" ;;
    --build-only) BUILD_ONLY=1 ;;
    --run) RUN_DIRECT=1 ;;
    --output) shift; [[ "$#" -gt 0 ]] || die "--output needs a value"; OUTPUT="$1" ;;
    --output=*) OUTPUT="${1#--output=}" ;;
    --cache-dir) shift; [[ "$#" -gt 0 ]] || die "--cache-dir needs a value"; CACHE_ROOT="$1" ;;
    --cache-dir=*) CACHE_ROOT="${1#--cache-dir=}" ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      PROGRAM_ARGS=("$@")
      break
      ;;
    -*) die "unknown option '$1' (try --help)" ;;
    *)
      if [[ -z "$SOURCE" ]]; then
        SOURCE="$1"
      else
        PROGRAM_ARGS+=("$1")
      fi
      ;;
  esac
  shift
done

[[ -n "$SOURCE" ]] || die "missing FILE.w (try --help)"
[[ -f "$SOURCE" ]] || die "source file not found: $SOURCE"
if [[ "$BUILD_ONLY" -eq 1 && "$RUN_DIRECT" -eq 1 ]]; then
  die "--build-only and --run cannot be combined"
fi
case "$DEBUGGER" in auto|lldb|gdb) ;; *) die "unsupported debugger '$DEBUGGER' (supported: auto, lldb, gdb)" ;; esac

SOURCE_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
SOURCE="$SOURCE_DIR/$(basename "$SOURCE")"
case "$CACHE_ROOT" in /*) ;; *) CACHE_ROOT="$CALLER_PWD/$CACHE_ROOT" ;; esac

if [[ -z "$OUTPUT" ]]; then
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  RUN_DIR="$CACHE_ROOT/runs/$STAMP-$$"
  mkdir -p "$RUN_DIR"
  STEM="$(basename "${SOURCE%.w}")"
  OUTPUT="$RUN_DIR/$STEM"
elif [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$CALLER_PWD/$OUTPUT"
fi
mkdir -p "$(dirname "$OUTPUT")"

echo "==> Debug build"
"$ROOT/bin/tungsten" compile "$SOURCE" --debug --frame-pointers --no-lto \
  --out "$OUTPUT"

[[ -x "$OUTPUT" ]] || die "compiler did not build $OUTPUT"
[[ -s "$OUTPUT.sidemap" ]] || die "missing or empty sidemap: $OUTPUT.sidemap"
if [[ "$(uname -s)" == Darwin ]]; then
  [[ -d "$OUTPUT.dSYM" ]] || die "missing debug-symbol bundle: $OUTPUT.dSYM"
fi

echo "binary: $OUTPUT"
echo "sidemap: $OUTPUT.sidemap"
if [[ "$BUILD_ONLY" -eq 1 ]]; then
  exit 0
fi
if [[ "$RUN_DIRECT" -eq 1 ]]; then
  if [[ "${#PROGRAM_ARGS[@]}" -eq 0 ]]; then
    exec "$OUTPUT"
  fi
  exec "$OUTPUT" "${PROGRAM_ARGS[@]}"
fi

if [[ "$DEBUGGER" == auto ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    DEBUGGER=lldb
  else
    DEBUGGER=gdb
  fi
fi
command -v "$DEBUGGER" >/dev/null 2>&1 || die "$DEBUGGER is not installed or not on PATH"

echo "==> Launch $DEBUGGER"
if [[ "$DEBUGGER" == lldb ]]; then
  if [[ "${#PROGRAM_ARGS[@]}" -eq 0 ]]; then
    exec lldb -- "$OUTPUT"
  fi
  exec lldb -- "$OUTPUT" "${PROGRAM_ARGS[@]}"
fi
if [[ "${#PROGRAM_ARGS[@]}" -eq 0 ]]; then
  exec gdb --args "$OUTPUT"
fi
exec gdb --args "$OUTPUT" "${PROGRAM_ARGS[@]}"
