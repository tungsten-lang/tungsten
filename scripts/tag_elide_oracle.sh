#!/usr/bin/env bash
# E4 (Phase 2.5): differential oracle for tag-guard elision.
#
# The compiler folds NaN-box tag guards proven by :structural tag facts
# (Phase 3). TUNGSTEN_TAG_ASSERT=1 is the elision-off lever: every guard
# that WOULD fold instead stays a live compare with llvm.trap wired to its
# disproven side. This script compiles a correctness set both ways with
# the same installed compiler and byte-compares the outputs:
#   - divergent output  => the fold changed behavior (unsound elision)
#   - a trap (SIGILL)   => a guard the fold called dead fired at runtime
# Either way the oracle fails loudly. It also checks the lever actually
# engaged (the assert-mode IR of a bigint program must contain llvm.trap)
# so a silently-dead lever cannot green-light anything.
#
# B10: TUNGSTEN_TAG_ASSERT must never build stage1/stage2 — build.rb
# clears it for stage builds; this script only compiles user programs.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
TMP="${TMPDIR:-/tmp}/tag-elide-oracle.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"

export TUNGSTEN_INCREMENTAL=0

SPECS=(
  spec/numeric/bigint_seam_disjoint_spec.w
  spec/compiler/overload_exact_tag_parity_spec.w
  spec/numeric/bigint_limb_sweep_spec.w
  spec/numeric/bigint_bang_spec.w
  spec/numeric/bigint_tag_sign_spec.w
  spec/numeric/bigint_identity_spec.w
  spec/numeric/rational_spec.w
)

fail=0

# Engagement sanity: the lever must visibly change the IR of a program
# whose guards fold (big_int.w's operator bodies).
probe=spec/numeric/bigint_seam_disjoint_spec.w
"$TUNGSTEN" --ll "$probe" > "$TMP/probe_fold.ll" 2>/dev/null
TUNGSTEN_TAG_ASSERT=1 "$TUNGSTEN" --ll "$probe" > "$TMP/probe_assert.ll" 2>/dev/null
if ! grep -q "llvm.trap" "$TMP/probe_assert.ll"; then
  echo "FAIL [oracle] TUNGSTEN_TAG_ASSERT=1 emitted no llvm.trap — the lever is dead" >&2
  fail=1
fi
if grep -q "tagassert" "$TMP/probe_fold.ll"; then
  echo "FAIL [oracle] default build contains tagassert blocks — lever leaked into normal mode" >&2
  fail=1
fi

for spec in "${SPECS[@]}"; do
  name="$(basename "${spec%.w}")"
  if ! "$TUNGSTEN" -o "$TMP/${name}_fold" "$spec" >/dev/null 2>&1; then
    echo "FAIL [$name] fold-mode compile failed" >&2; fail=1; continue
  fi
  if ! TUNGSTEN_TAG_ASSERT=1 "$TUNGSTEN" -o "$TMP/${name}_assert" "$spec" >/dev/null 2>&1; then
    echo "FAIL [$name] assert-mode compile failed" >&2; fail=1; continue
  fi
  "$TMP/${name}_fold" > "$TMP/${name}_fold.out" 2>&1
  st_fold=$?
  "$TMP/${name}_assert" > "$TMP/${name}_assert.out" 2>&1
  st_assert=$?
  if [ "$st_assert" -ne 0 ]; then
    echo "FAIL [$name] assert-mode run exited $st_assert (a folded guard fired?)" >&2
    tail -3 "$TMP/${name}_assert.out" >&2
    fail=1
  fi
  if [ "$st_fold" -ne "$st_assert" ]; then
    echo "FAIL [$name] exit codes diverge: fold=$st_fold assert=$st_assert" >&2
    fail=1
  fi
  if ! cmp -s "$TMP/${name}_fold.out" "$TMP/${name}_assert.out"; then
    echo "FAIL [$name] outputs diverge between fold and assert builds" >&2
    diff "$TMP/${name}_fold.out" "$TMP/${name}_assert.out" | head -10 >&2
    fail=1
  fi
  if grep -q "^FAIL" "$TMP/${name}_fold.out"; then
    echo "FAIL [$name] spec-level failures in fold build" >&2
    fail=1
  fi
  [ "$fail" -eq 0 ] && echo "PASS [$name]"
done

if [ "$fail" -ne 0 ]; then
  echo "tag_elide_oracle: FAILED" >&2
  exit 1
fi
echo "tag_elide_oracle: OK"
