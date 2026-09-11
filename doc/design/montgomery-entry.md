# Montgomery entry by shifting, and other MODEXP lessons

Source. The EIP-8200 MODEXP gas challenge (September 2026): a Lean-verified
EVM implementation of modular exponentiation where every operation has a
price, so the setup around the multiplications became visible in a way it
rarely is on a CPU. The shifted entry and selective table construction below
are implemented. The September 11 follow-up adds an exact-prime identity and
records which later arithmetic ideas fit Tungsten's existing kernels.

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

## 2. Build only the necessary prefix of the window table

The sliding window over `e` selects odd window values; a fixed exponent such
as `65537 = 2^16 + 1` only ever selects the window `1`, so the table rows
`b³, b⁵, …` — and the `b²` that seeds them — are pure setup. Replaying the
window selection without arithmetic (`w_powm_table_rows_used`) costs a scan
of the exponent bits and finds the highest selected row. Build the prefix
through that row, including intermediate powers needed to reach it. An
exponent that only selects row zero avoids the seed square and all additional
table multiplies.

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

## Exact-prime identity and final transfer audit (2026-09-11)

`bigint_powmod_any` now recognizes `e = p - 1` for exactly the BN254 and
secp256k1 **base-field** primes. For either prime, the result is zero when
`p` divides the base and one otherwise. The runtime reduces oversized bases
before checking the nonzero residue, compares all four modulus and exponent
limbs, and retains the existing signed-base and absolute-modulus semantics.
Any allocated remainder is released on the new exit. The existing
`BN_ALGEBRAIC_IDENTITY_FAST=0` switch also disables this shortcut.

The constants come from [EIP-196](https://eips.ethereum.org/EIPS/eip-196)
and [Standards for Efficient Cryptography 2, version 2.0, section 2.4.1](https://www.secg.org/sec2-v2.pdf).
This is an exact dispatch on two known primes; it does not assume that an
arbitrary odd input is prime. In particular, `2^14 mod 15` remains 4.
Exponent zero, modulus one, and the existing one/negative-one shortcuts
retain their earlier ordering. `modpow` remains a variable-time general
integer operation.

### Representation determines what transfers

Tungsten's `WBigint` stores little-endian **64-bit** limbs, a signed length,
capacity and ownership metadata (`runtime/wvalue.h`). Small integers use the
immediate representation. The MODEXP EVM kernel instead uses **256-bit**
words: its eight-limb RSA-2048 workload corresponds to **32 Tungsten limbs**.
An EVM crossover at eight limbs is not evidence for a CPU crossover at eight.

| MODEXP lesson | Tungsten disposition |
| --- | --- |
| Use a symmetric square, computing each cross product once | Already implemented by the square dispatcher and dedicated Montgomery square paths. For n limbs there are n(n+1)/2 distinct products, but doubling cross terms must preserve the extra carry bit. |
| Fuse multiplication, reduction and repeated-square work | `w_powm_mont_sqr`/`w_powm_mont_mul` already use raw rows through the entire ladder; fixed four-limb fused kernels and architecture-specific reduction schedules already exist. Benchmark a complete ladder before replacing them. |
| Prepare the modulus, inverse and table once | The context and raw-row ladder already do this. The new entry removes unused setup, and `w_powm_table_rows_used` limits construction to the highest row selected by the exponent. Intermediate residues remain in the Montgomery domain. |
| Truncate products whose low half is discarded by REDC | `w_powm_redc_mullo`, `w_mullo_n` and the Newton inverse already provide a separate path for sufficiently large even limb counts. A different truncation formula must beat that existing implementation including inverse setup and the carry into the retained half. |
| Use narrower limbs to accumulate more products before carrying | A research option for a separate kernel or numeric representation. It changes conversion, limb count, carry bounds and scratch layout; it is not a drop-in change to `WBigint`. |
| Materialize constants and unroll hot loops | EVM gas may reward a much larger immediate. CPU instruction selection, register pressure and instruction-cache behavior need their own measurements; EVM byte/gas tradeoffs do not set CPU thresholds. |
| Replace arithmetic selection by a lookup | Charge table initialization, loads and actual hit count. A two-entry MODEXP table saved only 67 gas per measured corpus because its byte loop was entered twice. No CPU lookup optimization is inferred from this. |

The EVM profile also exposed substantial stack traffic: DUP/SWAP/POP consumed
222,548 of 576,003 executed gas (38.6%) in the profiled candidate. Those opcode
totals overlap arithmetic regions; they must not be added to the region
totals. CPU register moves have a different cost, but the transferable
question is whether a hot loop can retain a value across its caller/callee
boundary and eliminate repeated loads or representation conversions.

### Higher-order arithmetic and public research

[BearSSL's bigint design](https://www.bearssl.org/bigint.html) explains how
unused limb bits can make fused product accumulation and carry management
cheaper. In the MODEXP experiments, a 17-digit radix-2^124 kernel with cached
modulus decoding reached 567,446 native gas, but failed the unchanged loader
and lacked the complete proof. A radix-2^127 whole-column accumulator
overflowed 256 bits in a concrete check. These observations support bounding
the entire accumulator, including carry-in, before coding such a kernel;
they are not shipped Tungsten performance results.

[Didier et al., truncated Montgomery multiplication](https://arxiv.org/html/2410.18129v1#S5)
is relevant to batch modular arithmetic and high/low product scheduling. Its
implementation uses AVX512 VPMADD52 and word-sliced batches. Its throughput
results do not transfer directly to one scalar Apple-arm64 exponentiation.
Compare against Tungsten's existing truncated reducer before adding another.

[Dumas, Fousse and Salvy, simultaneous reduction and Kronecker substitution](https://arxiv.org/abs/0809.0063)
provides the useful matmul idea: pack bounded coefficients into integer slots
and extract convolution coefficients from a wider product. For example, eight
unsigned 14-bit coefficients in 31-bit slots have maximum column sum
`8 * (2^14 - 1)^2 < 2^31`; reversing one vector puts its dot product in the
middle slot. Packing/loading, signed coefficients, output width and carries
must all be included in a real implementation. This is a possible
small-coefficient matrix kernel, not a substitute for arbitrary BigInt
multiplication or a measured Tungsten matmul gain.

The [WHIR-over-a-31-bit-field report](https://ethresear.ch/t/evm-verification-of-whir-over-a-31-bit-field/24902)
offers an EVM example of delayed reduction and fused extension-field
operations. Its custom `EXTFIELD_MAC` precompile is not available to ordinary
EVM code in this challenge. Its headline transaction-gas saving also differs
from executed gas: the small-field comparison reports higher execution gas.
The portable lesson is to amortize unpacking and reduction within an operation
whose input/output bounds are known, then measure the complete operation.

### Validation and code-generation lessons

The challenge's full proof found a relocation error missed by both the fixed
44 vectors and 100 matched seeds: a generic-path return address was left at
320 after its target moved to 302. Elsewhere, 320 really was a data address.
Relocation must follow each operand's **role**, not just its integer value.
A separate generator bug used a semantic jump remapping for a physical slice
end and produced a negative slice length. Keep physical byte/instruction
boundaries distinct from control-flow destinations and reject invalid slice
ranges before invoking a prover. These are useful invariants for any code
emitter; they do not establish a bug in Tungsten's emitter.

Regression coverage should partition dispatch conditions: zero/one values,
negative and oversized bases, even moduli, exact special primes, near-miss
primes/exponents, and representation/admission boundaries. More random seeds
from one corpus generator did not exercise that generic even-modulus path.
Keep the exact source and bytecode hashes fixed while checking; finite output
tests, a complete theorem and remote scoring are separate kinds of evidence.
The 574,366 EVM candidate had matched local outputs and focused proofs at this
handoff, but no completed universal theorem or accepted submission. The
574,299 lookup variant was native-only. Neither is recorded as a leaderboard
win here.

Tungsten's focused checks are:

```sh
bin/tungsten compile spec/numeric/bigint_powmod_spec.w --no-lto --out /tmp/powmod-spec
/tmp/powmod-spec
bin/tungsten compile spec/numeric/bigint_powmod_entry_spec.w --no-lto --out /tmp/entry-spec
/tmp/entry-spec
bin/tungsten compile spec/numeric/bigint_prime_spec.w --no-lto --out /tmp/prime-spec
/tmp/prime-spec
python3 benchmarks/big_math/check_modexp_learnings.py --out build/modexp-oracle
make -C runtime bench-powmod
runtime/bench_powmod --block 'k=8 e=full(512 bits)' 5000
```

The independent Python oracle emits a retained fixture and checks results and
input preservation in debug and release/native/fast builds. It includes
signed/divisible bases, per-bit guard misses, even moduli, and widths around
the register, Montgomery, truncated-REDC and Barrett boundaries. Its output
directory must be new so a failed run cannot be silently overwritten.
`bench_powmod` includes the two Fermat hits and ordinary `p - 2` misses;
its timings are a focused diagnostic, not broad bignum qualification.
The `--block` form selects one case and a fixed iteration count for paired
measurements; retain checksums and reject mismatches between variants.

### Retained landing evidence

All 73 fixed powmod checks, 32 entry cases and the prime spec passed on the
remote-main-based landing branch. The 132-case oracle passed in both debug
and release/native/fast builds, including input preservation. Spec
classification also passed. This is focused validation of these changes.

The [initial three-round diagnostic](../../benchmarks/big_math/baselines/modexp-transfer-20260911.json)
retains all 117 observations, source hashes and its exact harness. For base 2,
the two Fermat hits fell from approximately 5.5/5.7 microseconds before the
shortcut to 0.0061/0.0054 microseconds. Short ordinary-control blocks were
noisy on a host also running Lean, so the apparent regressions were retained
and investigated rather than discarded.

The [paired control follow-up](../../benchmarks/big_math/baselines/modexp-transfer-20260911-paired-controls.json)
uses nine alternating ABBA/BAAB rounds, equal iteration counts within each
comparison, and blocks calibrated to at least 110 ms on the faster pilot.
It covers the apparent losses plus both `p - 2` guard misses. Its five
candidate/pre-Fermat median ratios range from 0.9941 to 1.0065. Against the
earlier remote main, the corresponding worst median ratio is 1.0294; the
16-limb `e=3` entry path improves to 0.5715. Every paired checksum matches.
These measurements establish a bounded comparison on this host, not a
completed all-operations bignum performance qualification.
