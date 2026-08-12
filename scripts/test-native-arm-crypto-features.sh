#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "SKIP native ARM crypto feature contract (requires macOS arm64)"
  exit 0
fi

OUT_DIR="$ROOT/build/cache/native-arm-crypto-features"
IR="$OUT_DIR/probe.ll"
mkdir -p "$OUT_DIR"

"$ROOT/bin/tungsten" --release --native --ll \
  "$ROOT/compiler/test/fixtures/arithmetic.w" > "$IR"

attrs="$(grep -m1 '^attributes #0 = ' "$IR" || true)"
if [[ -z "$attrs" ]]; then
  echo "FAIL native ARM crypto feature contract: missing function attributes" >&2
  exit 1
fi

for feature in aes sha2; do
  if [[ "$attrs" != *"+$feature"* ]]; then
    echo "FAIL native ARM crypto feature contract: missing +$feature" >&2
    echo "$attrs" >&2
    exit 1
  fi
done

if [[ "$attrs" != *'"target-cpu"='* || "$attrs" == *'"target-cpu"="generic"'* ]]; then
  echo "FAIL native ARM crypto feature contract: target CPU was not specialized" >&2
  echo "$attrs" >&2
  exit 1
fi

cpu="$(printf '%s\n' "$attrs" | sed -n 's/.*"target-cpu"="\([^"]*\)".*/\1/p')"
echo "PASS native ARM crypto feature contract (target-cpu=$cpu, +aes, +sha2)"
