#!/usr/bin/env bash
set -euo pipefail

count_file="${TUNGSTEN_TARGET_FAKE_COUNT:?set TUNGSTEN_TARGET_FAKE_COUNT}"
count="$(sed -n '1p' "$count_file" 2>/dev/null || true)"
if [[ -z "$count" ]]; then
  count=0
fi
printf '%s\n' "$((count + 1))" > "$count_file"

cat <<'LLVM'
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx15.0.0"

define void @__tungsten_probe() #0 {
  ret void
}

attributes #0 = { "target-cpu"="apple-m4" "target-features"="+aes,+crc,+fp-armv8,+neon,+sha2" "tune-cpu"="apple-m4" }
LLVM
