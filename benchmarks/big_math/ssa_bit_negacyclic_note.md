# Feasibility note: SSA bit-granular negacyclic rings (time-boxed, no implementation)

2026-08-11 · scoping only — multi-week project; this is the go/no-go analysis
today's dispatcher and kernel structure support.

## Where SSA stands

`bn_ssa_mul` works in Z/(2^K+1) with limb-quantized residues (m = K/64
limbs per point, +1 top limb). Ring size K is already chosen from TWO
granularity families (`ssa_choose`, runtime.c:8306): K a multiple of L/2
(plain 2^j twiddles) or of L/4 via the √2 = 2^(3K/4) − 2^(K/4) identity
(`ssa_shl_half`, runtime.c:8248) — odd half-exponents cost one extra
shift+subtract, only in the finest stage. SSA owns the >= 16384-limb band
(with parallel Toom-4) and is the thing GMP beats us with elsewhere;
forced NTT never wins in-band (see goldilocks note).

"Bit-granular negacyclic" = freeing K from the L/4 lattice entirely: pick
K = ceil(128w + log2(L) + 2) exactly (any bit value), absorbing the
fractional twiddle exponents 2K/L into per-butterfly bit-rotations. The
prize is the K-rounding waste: today K rounds UP to the next multiple of
max(L/4, 64) bits.

## What the numbers say about the prize

- The rounding waste is at most granv−1 bits per residue, i.e. < 1 extra
  limb when granv = 64 (small L), and up to L/4 bits when L is large. At
  the decision sizes (L = 2048..8192, w = 16..64, K ≈ 128w+k+2 ≈ 2-8K
  bits): granv = L/4 = 512..2048 bits → worst-case waste ≈ 8-32 limbs on
  m ≈ 32-128 limbs. **Upper bound ~15-25% of butterfly bandwidth, average
  ~half that** (waste is uniform in [0, granv)). That is the entire
  theoretical prize; the average case nets ~6-12%.
- The model already prices the finer of the two existing families as a
  LOSS at scale: `ssa_choose` multiplies the L/4-family cost by 1.10 for
  L >= 2048 because the extra odd-twiddle pass is memory-bound (measured
  16384 limbs: 2.23 ms plain vs 2.34 ms half-family — runtime.c:8325).
  Bit granularity is the same trade pushed further: every twiddle in
  every stage becomes a funnel-shifted (non-limb-aligned) traversal, not
  just the finest stage's odd exponents.
- A bit-granular butterfly replaces limb-aligned `bn_add_n`/`bn_sub_n`/
  word-`memmove` twiddles with bit-offset funnel walks. The Exp-2 funnel
  probe work in this campaign measured LLVM's vectorized funnel walk at
  roughly parity with aligned copies per limb — but the negacyclic twist
  also forces read-modify-write joins at both residue ends and kills the
  clean `ssa_addsub` aliasing pattern. Estimated butterfly cost growth:
  +20-40%, against the ~6-12% average bandwidth saving.

## What would have to be true to win in-band

The bandwidth saving must exceed the per-butterfly overhead, i.e. the
waste fraction must exceed ~20-40% SUSTAINED — only true immediately after
a transform-length doubling (the 20480-24576, 32769-40960 style bands the
NTT model comment names). A cheaper alternative for exactly those bands
already exists inside the current lattice: allow K multiples of L/8 with a
fourth root of 2 (exists when 8 | K via the same identity pattern), which
costs one more shift+sub only on the two finest stages. If those bands
matter, measure the L/8 family first — it is a ~30-line extension of
`ssa_shl_half`/`ssa_choose`, not a rewrite.

## Condition to reopen

A profile showing >= 20% of a real workload's time inside SSA cells that
sit just past a transform-length doubling, AND the L/8-family extension
measured insufficient there. Otherwise the negacyclic rewrite's overhead
exceeds its average prize by construction.
