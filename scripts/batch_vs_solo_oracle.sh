#!/usr/bin/env bash
# Batch-vs-solo oracle: `compile-batch` must produce byte-identical .ll
# for every file to what a fresh per-file `compile` produces. This is the
# structural gate for all batch/warm-core work (incremental lowering):
# any state leaking across compiles in one process — emitter
# metadata, mod residue, arena effects — shows up here as a byte diff.
#
# Usage: scripts/batch_vs_solo_oracle.sh [spec.w ...]
# Default corpus: a representative shard incl. fused-elementwise specs
# (the alias-scope leak's trigger surface) and bignum/typed-overload.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-batch-oracle.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export TUNGSTEN_INCREMENTAL=0

SPECS=("$@")
if [[ ${#SPECS[@]} -eq 0 ]]; then
  SPECS=(
    spec/compiler/elementwise_fusion_spec.w
    spec/numeric/bigint_seam_disjoint_spec.w
    spec/compiler/overload_exact_tag_parity_spec.w
    spec/compiler/typed_overload_hosts_spec.w
    spec/numeric/rational_spec.w
    spec/compiler/masked_index_loop_spec.w
    spec/compiler/loop_version_array_spec.w
    spec/numeric/fp_math_mode_spec.w
  )
fi

fail=0

# Both sides compile the SAME scratch copies: embedded source paths land
# in string constants and the static slab, so compiling the repo path
# solo but the copy in batch diffs on path bytes alone. Copies also keep
# batch's <src>.wc outputs out of the repo.
mkdir -p "$TMP/solo" "$TMP/batch" "$TMP/src"
declare -a BATCH_SRCS=()
for f in "${SPECS[@]}"; do
  n="$(basename "${f%.w}")"
  cp "$f" "$TMP/src/$n.w"
  BATCH_SRCS+=("$TMP/src/$n.w")
done

# Solo: one fresh process per file.
for f in "${SPECS[@]}"; do
  n="$(basename "${f%.w}")"
  if ! TUNGSTEN_LL_PATH="$TMP/solo/$n.ll" "$TUNGSTEN" compile "$TMP/src/$n.w" --out "$TMP/solo/$n" >/dev/null 2>&1; then
    echo "FAIL [$n] solo compile failed"; fail=1
  fi
done
export TUNGSTEN_LL_DIR="$TMP/llroot"
if ! "$TUNGSTEN" compile-batch "${BATCH_SRCS[@]}" >"$TMP/batch.log" 2>&1; then
  echo "FAIL [batch] compile-batch exited nonzero:"; tail -5 "$TMP/batch.log"; fail=1
fi

for f in "${SPECS[@]}"; do
  n="$(basename "${f%.w}")"
  bll="$(ls -t "$TMP/llroot/$n.ll" "$TMP"/llroot/*/"$n.ll" 2>/dev/null | head -1)"
  if [[ -z "$bll" ]]; then
    echo "FAIL [$n] batch .ll not found under $TUNGSTEN_LL_DIR"; fail=1; continue
  fi
  if [[ ! -f "$TMP/solo/$n.ll" ]]; then
    continue
  fi
  if cmp -s "$TMP/solo/$n.ll" "$bll"; then
    echo "PASS [$n] batch == solo"
  else
    echo "FAIL [$n] batch .ll differs from solo ($(diff "$TMP/solo/$n.ll" "$bll" | wc -l | tr -d ' ') diff lines)"
    diff "$TMP/solo/$n.ll" "$bll" | head -8
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then echo "batch_vs_solo_oracle: FAIL"; exit 1; fi
echo "batch_vs_solo_oracle: OK"
