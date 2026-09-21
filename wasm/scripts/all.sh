#!/bin/bash
# Dev loop: run a subset of build steps. Usage: all.sh [host] [ir] [cc] [rt] [link]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/wasm/scripts"
for step in "$@"; do
  case "$step" in
    host) "$S/build_host.sh" | tail -1 ;;
    ir)   "$S/emit_ir.sh" | tail -1 ;;
    cc)   "$S/compile_ir.sh" | tail -1 ;;
    rt)   "$S/compile_runtime.sh" | tail -3 ;;
    link) "$S/link.sh" ;;
    *) echo "unknown step $step"; exit 2 ;;
  esac
done
