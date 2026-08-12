# Feasibility note: Goldilocks NTT radix-4/NEON port (time-boxed, no implementation)

2026-08-11 · scoping only — this is a multi-week project and this note is the
honest go/no-go analysis the dispatcher data supports today.

## What the dispatcher cost model says today

The shipped Goldilocks path is radix-2 DIF/DIT plain C (`runtime.c`, "Goldilocks
single-prime NTT" block). The historical radix-4 + 2^48 shift-twiddle +
whole-pass-asm kernel from the bigmul campaign (doc/articles/bignum-multiply.md)
was never ported into the runtime; the port is what this note scopes.

The dispatcher (`bn_top_choice`, runtime.c:8378) structurally caps what any
NTT speedup can buy:

- Below `BN_PAR_TOOM_LIMIT` (16384 limbs) the answer is Toom by fiat — the
  bounded point scheduler keeps seven-way parallel Toom-4 ahead through ~14K
  limbs (measured, comment at runtime.c:8382).
- In the reachable band (>= 16384), the calibration comment at
  runtime.c:8340 records the forced-kernel sweep: NTT/SSA/Toom =
  6.8/1.1/1.6 ms at 16384, 4.4/1.6/1.9 at 24576, 9.4/3.4/2.9 at 32769,
  21.9/7.3/7.4 at 65537, 50/16/20 at 131073. **Forced NTT never wins
  in-band** — it trails the winner by 2.5-6x, and the kernel runs 3.2-5.6x
  its small-n calibration up there (cache-resident assumptions break).

## What would have to be true to win in-band

The port would need the one-shot transform to get **>= 3x faster at
16K-131K limbs** to displace SSA/parallel-Toom anywhere the dispatcher can
route to it. The evidence says the available mechanisms cannot stack to 3x:

- Radix-4 with the 2^48 shift-twiddle removes ~1/4 of the gmuls and turns
  quarter-turns into shift-folds. The bigmul campaign measured the whole
  radix-4+asm package as the last ~25% after inlining (the 4.8x jump came
  from butterfly inlining, already present in the runtime port). Call it
  1.3-1.6x.
- 4-lane NEON on 64-bit Goldilocks is blocked by the cross-register-file
  transfer cost (article, "Multi-prime NTT" section): 64x64->128 products
  need scalar `mul`/`umulh`, so lanes bounce between vector and scalar
  files. The 2.4-3.8x NEON win exists only at 32-bit coefficients, where a
  multiply needs 3 transforms x 3 primes (or 9 with CRT) and the win erodes
  to break-even. Nothing since (M5 included: no 64-bit vector multiply
  high) changes this.
- The in-band deficit is also bandwidth-shaped: at L >= 2^19 points the
  transform is streaming 4-8 MiB per pass, and the measured 3.2-5.6x
  calibration drift is the memory system, which radix reorganization does
  not remove (radix-4 saves passes — the strongest part of its case — but
  SSA's add/shift butterflies stream the same data with far cheaper ops).

Net: 1.3-1.6x (radix-4) x ~1.0x (NEON blocked at 64-bit) < 3x. **No-go for
the CPU dispatcher band.** The squaring column (one forward transform) has
the same shape at half the deficit — still short.

## Where the work WOULD pay (out of scope here)

- The amortized/fixed-operand context (twiddle + one-operand transform
  reuse, e.g. repeated mulmod by a fixed modulus): the article's ladder had
  gold-NTT amortized >= 2048 limbs. A radix-4 port helps there, but that
  dispatcher context does not exist in the runtime today.
- GPU Goldilocks (already 1.31x faster than GMP for the twin-prime engine's
  real workload, per the article) is where the radix-4 butterfly structure
  is already used.

## Condition to reopen

A measured >= 3x one-shot transform speedup at 16384 limbs from a prototype
stage (e.g. a standalone radix-4 pass over L=2^15..2^17 with production
twiddle layout), or a dispatcher context where transforms amortize across
calls. Short of that, tuning BN_NTT_THRESHOLD or the 4.8 ns calibration
constant cannot make the port reachable — the model was deliberately
recalibrated (see the runtime.c:8340 comment) to stop NTT from stealing
cells at transform-length doublings.
