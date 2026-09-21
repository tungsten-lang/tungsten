#!/bin/bash
# Step 5: tungsten.raw.wasm -> wasm/tungsten.wasm (optimize with wasm-opt when
# available, then strip the name/producers sections) + size report.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/wasm/scripts/config.sh"
B="$ROOT/wasm/build"
OUT="${1:-$ROOT/wasm/tungsten.wasm}"
WASM_OPT_BIN="${WASM_OPT_BIN:-$(command -v wasm-opt || true)}"
if [ -z "$WASM_OPT_BIN" ] && [ -x "$ROOT/wasm/toolchain/node_modules/.bin/wasm-opt" ]; then
  WASM_OPT_BIN="$ROOT/wasm/toolchain/node_modules/.bin/wasm-opt"
fi
cp "$B/tungsten.raw.wasm" "$B/tungsten.opt.wasm"
if [ -n "$WASM_OPT_BIN" ] && [ "${WASM_SKIP_WASM_OPT:-0}" != "1" ]; then
  # Features are read from the module's target_features section.
  "$WASM_OPT_BIN" "${WASM_OPT_PASSES:--O2}" --detect-features "$B/tungsten.raw.wasm" -o "$B/tungsten.opt.wasm"
  echo "wasm-opt ${WASM_OPT_PASSES:--O2}: $(wc -c < "$B/tungsten.raw.wasm") -> $(wc -c < "$B/tungsten.opt.wasm") bytes"
else
  echo "wasm-opt not found: skipping (npm --prefix wasm/toolchain install binaryen)"
fi
"$WASM_LLVM/llvm-objcopy" --strip-all "$B/tungsten.opt.wasm" "$OUT"
printf '%s: %s bytes raw, %s bytes gzip -9\n' "$OUT" "$(wc -c < "$OUT" | tr -d ' ')" "$(gzip -9 -c "$OUT" | wc -c | tr -d ' ')"
