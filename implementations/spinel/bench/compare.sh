#!/bin/sh
# compare.sh — run all mini_interp env-strategy variants through the same
# compile + correctness-check + median-timing flow and print a table.
#
# Variants (same fib(33)+sumloop(10M) workload):
#   mini_interp           naive string-keyed hash env (from-scratch walker)
#   mini_interp_ic        slot + runtime inline cache (≈ real Tungsten interp)
#   mini_interp_slots     statically pre-resolved slot (lever-1 ceiling)
#   mini_interp_poolframe slot+IC, RECYCLED frames + direct args (≈ real interp's POOLS)
#   mini_interp_pool      contiguous value-stack, zero per-call alloc (lever-3 proper)
#   mini_interp_poly      value-stack but poly value domain (lever-2 poly-value tax)
#
# Findings (2026-06-15) — every matz #282 lever now measured:
#   hash->ic        ~38%  lever-1 ALREADY captured by the real interp
#   ic->slots       ~1%   static slot resolution adds ~nothing (noise)
#   ic->poolframe   ~42%  lever-3 ALREADY captured by sp_Environment + args pools
#   poolframe->pool ~5%   true value-stack adds only this over pooling (near noise; NOT worth a rewrite)
#   pool->poly      +31%  poly-VALUE tax (NaN-box + tag-dispatched arith); fundamental to dynamic typing
# Profile: ~61% of self-time was malloc/free/GC from per-call frames+args.
# Conclusion: 3 of 4 levers are done/near-done in the real interp; the 30x
# gap is architectural (needs a bytecode VM), not lever-tuning.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
RUNS="${RUNS:-7}"
for v in mini_interp mini_interp_ic mini_interp_slots mini_interp_poolframe mini_interp_pool mini_interp_poly; do
  line=$(RUNS="$RUNS" LABEL="$v" "$DIR/run_mini_interp.sh" "$DIR/$v.rb" 2>&1 | grep median | sed 's/^ *//')
  printf "%-20s %s\n" "$v" "$line"
done
