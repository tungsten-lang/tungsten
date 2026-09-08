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
