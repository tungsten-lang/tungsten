# Montgomery entry by shifting, and other MODEXP lessons

Source. The EIP-8200 MODEXP gas challenge (September 2026): a Lean-verified
EVM implementation of modular exponentiation where every operation has a
price, so the setup around the multiplications became visible in a way it
rarely is on a CPU. Four of those lessons transfer; the first two are now in
the runtime.

## 1. Enter Montgomery form by shifting, not by R²

The textbook entry into Montgomery form computes `R² = B^2k mod n` (one
2k-by-k division) and then `MontMul(x, R²) = x·R mod n` (one Montgomery
multiply), plus `R mod n = MontMul(R², 1)` when the ladder starts from one.
For an exponentiation with a few hundred multiplies that is noise; for the
RSA public exponents 3 and 65537 it was most of the call.

`x·R mod n` is `x·B^k mod n`: shift `x` up by `k` limbs and reduce. On the
EVM that was done one limb at a time (multiply by `B`, estimate the quotient
from the top two limbs with a precomputed inverse of the odd part of the
modulus' top limb, subtract `q·n` as a multiply-accumulate against `-n`,
repair any estimate error with add/subtract rounds). In the C runtime a
single division of the shifted operand does the same job, because
`mag_divmod` already carries the Möller–Granlund reciprocal quotient
estimate. `bigint_powmod_any` now:

- initialises its modulus context in a `powm_only` mode that skips `μ`, `R²`,
  `R mod n` and `(n-1)·R mod n` when the ladder is Montgomery (odd modulus,
  3 limbs and up; `w_prime_modctx_init_cap_mode`);
- enters the domain with `w_powm_mont_enter`: `x·B^k mod n` by one division.

Prime testing (`Int#prime?`, Miller–Rabin) keeps the full context: it needs
`R mod n` and `(n-1)·R mod n` as comparison values.

## 2. Build only the window-table rows the exponent uses

The sliding window over `e` selects odd window values; a fixed exponent such
as `65537 = 2^16 + 1` only ever selects the window `1`, so the table rows
`b³, b⁵, …` — and the `b²` that seeds them — are pure setup. Replaying the
window selection without arithmetic (`w_powm_table_rows_used`) costs a scan
of the exponent bits and removes one squaring and `t-1` multiplies for every
exponent whose windows never reach the higher rows.

Measured with `make bench-powmod` (`runtime/bench_powmod.c`, Apple M-series,
best of three interleaved rounds, microseconds per call):

| shape | before | after |
| --- | ---: | ---: |
| 8 limbs, e=3 | 0.44 | 0.32 |
| 8 limbs, e=65537 | 1.12 | 0.91 |
| 16 limbs, e=3 | 1.03 | 0.57 |
| 16 limbs, e=65537 | 3.07 | 2.14 |
| 32 limbs, e=3 | 3.44 | 1.65 |
| 32 limbs, e=65537 | 10.34 | 7.77 |
| 32 limbs, 2048-bit e | 1012 | 994 |

Results are bit-identical (`spec/numeric/bigint_powmod_entry_spec.w`
cross-checks 32 shapes against independently computed values).

## 3. Carry-folded multiply-accumulate for carry-less targets

A limb step `t + x·y + c` needs the 128-bit product and two carries. Without
a carry flag or a 128-bit add (the EVM, and any GPU dialect without `u128`)
each carry is a comparison. Forming the sum as `(x·y_low + c) + t` instead of
`c + (t + x·y_low)` gives the same stored word, and although the two
overflow bits differ individually their sum is the same, so the carry can be
folded into the high word with subtractions rather than tested twice. It
saved 5 of 42 instructions per limb step on the EVM. It is the shape to use
for a multi-limb Montgomery multiply in an `@gpu fn` kernel (MSL has `mulhi`
but no 128-bit integers). With `__uint128_t` on the CPU the compiler already
does this, so the runtime kernels are unchanged.

## 4. An exact one-limb quotient without a wide division

Where a 128-by-64 division is unavailable but a modular multiply of full
words is (the EVM has `mulmod`; a GPU kernel could emulate one), the top-two-
limb quotient `⌊(u₁B + u₀)/d⌋` can be computed exactly: split `d = L·d_odd`
with `L` a power of two, shift `u` down by `L` (two shifts and one small
multiply), take `u mod d_odd` with a modular multiply by `B mod d_odd`, and
finish with an exact (Jebelean) division by `d_odd` using its inverse modulo
`B`, obtained by Newton iteration once per modulus. Eight word multiplies
replace the division. The runtime does not need this (it has the reciprocal
quotient estimate), but it is the recipe if big-integer reduction ever moves
onto a GPU dialect.

## Robustness pattern

The EVM routine never proves its quotient estimate exact: it subtracts `q·n`
for whatever `q` the estimate produced and then repairs with add/subtract
rounds that provably terminate for any `q`. The correctness proof depends
only on the repair loop; the estimate's quality only affects cost. That
separation — an oracle that is cheap and usually right, a fix-up that is
always right — is worth copying whenever a numeric shortcut is hard to
certify.

## Follow-up lessons from the next day's frontier (2026-09-08)

Competitors built on the shifted-entry routine within hours; their notes and
diffs add four things worth keeping.

- **Measure the hard limit before the proof.** A native speedup that cannot
  pass the unchanged artifact generator is not a result. One team lost a
  6.7 KB candidate to the ~5.5 KB elaboration cap after its kernel was done;
  the working version removed a superseded specialization to make room. Any
  pipeline with a fixed-cost gate (artifact size, proof budget, kernel
  register file) should be probed with a throwaway artifact first.
- **Size-versus-speed by per-site measurement, then a knapsack.** Every
  constant site was encoded short (complement plus `NOT`) as the common base,
  each site was restored to the wide encoding alone and scored, and a 0/1
  knapsack over (measured gas benefit, byte cost) chose the layout under the
  size budget. The predicted sum matched the measured total. The same recipe
  applies to any code-size budget with per-site costs: unrolling and inlining
  decisions, GPU kernel constant hoisting, `bits` optimization flags.
- **Padding is not free: pad with a cheaper wide encoding, not a no-op.** The
  frontier keeps instruction boundaries by widening a `PUSH` immediate
  (`PUSH7` of a small constant) instead of inserting `JUMPDEST`s; the wide
  push costs the same 3 gas as the short one, the no-op costs one more every
  time it executes. Same idea as choosing alignment padding that lives in
  never-executed slots.
- **Saturate an estimate that can wrap.** The quotient estimate of the
  shifted entry is a word; if the top-limb comparison shows the true quotient
  would exceed the word, clamp the estimate to all-ones instead of letting it
  wrap. The repair rounds already accept any estimate, so this changes cost,
  not correctness: a wrapped estimate would need on the order of `B` add
  rounds, a saturated one at most a few subtract rounds. Section 4's recipe
  should include this clamp whenever the dividend is not known to keep the
  quotient below the radix.

Commutativity was also mined for stack shuffles (an `ADDMOD` operand swap
elided, two gas per estimate); that is a stack-machine concern with no
counterpart in Tungsten's register lowering.
