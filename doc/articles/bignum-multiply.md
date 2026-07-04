# A fast bignum multiply in Tungsten: 118× → ~3× of GMP

This is the story of building a fast arbitrary-precision integer multiply natively in
Tungsten — to replace gmpy2/GMP in a twin-prime primality engine, whose inner loop is
dominated by modular squarings of `k·2ⁿ±1`. It is also an honest account of where the
effort hit a ceiling, why, and what that says about the language's codegen.

## The result

Best single-threaded CPU multiply is a **Goldilocks single-prime NTT** (one 64-bit
word per coefficient, canonical radix-4 butterflies with a `2⁴⁸` shift-twiddle, a
whole-pass hand-asm stage, amortized twiddle tables), dispatched by a benchmark-swept
ladder:

```
schoolbook ≤32 limbs → Karatsuba 48–256 → Toom-3 90–300 → Toom-4 300–5000
  → Toom-6 ≥5000 → gold NTT (one-shot ≥16384 limbs; amortized ≥2048; squaring ≥1024)
```

Measured best-of-stack vs GMP 6.3 (µs/op, same machine, warmed, back-to-back):

| size  | our mul | our square | GMP  | mul gap | square gap |
|-------|---------|-----------|------|---------|-----------|
| 64k   | 222     | 197       | 88   | 2.5×    | 2.2×      |
| 256k  | 1318    | 903       | 283  | 4.6×    | 3.2×      |
| 512k  | 2814    | 2031      | 632  | 4.5×    | 3.2×      |
| 1M    | 6146    | 4146      | 1339 | ~3×     | 3.1×      |

The engine's actual operation — **squaring** — is the closest, ~2.2–3.2×, because a
square needs one forward transform instead of two. (For the engine's *real* workload the
GPU Goldilocks path already runs 1.31× **faster** than GMP; this article is about the CPU.)

## The ladder, rung by rung

- **Schoolbook → Karatsuba → Toom-3 → Toom-4 → Toom-6.** Standard Toom-Cook with
  signed-magnitude interpolation and exact division by small constants. Each rung lowers
  the exponent (Toom-4 ≈ n^1.40, Toom-6 ≈ n^1.34). Profiling settled a long-running
  question: the Toom ladder is **subproduct-bound**, not basecase- or recombination-
  bound — its time is the 7-way (Toom-4) recursion tree, matching its theoretical
  exponent. Hand-asm on the basecase changed full-ladder time ~0% (the basecase is <5%);
  fusing recombination passes changed it ~0% (recombination is ~4.6%). Earlier claims to
  the contrary were measurement artifacts (see Lessons).
- **Goldilocks NTT.** Prime `P = 2⁶⁴ − 2³² + 1`: `mulmod` is `mul`+`umulh` then a fold
  using `2⁶⁴ ≡ 2³²−1`, `2⁹⁶ ≡ −1`. One machine word per coefficient. Inlining the
  butterfly (eliminating per-op calls) was a 4.8× jump; canonical radix-4 with the
  `2⁴⁸` 4th-root-of-unity as a shift-reduce (not a gmul) and a whole-pass hand-scheduled
  asm stage took it the rest of the way. This is the FFT rung; it overtakes Toom-4 around
  131k–1M bits depending on one-shot vs amortized.

## What didn't work — and why it's the interesting part

Three FFT alternatives were each built, validated, and measured to *lose* to the gold
NTT on this codegen. The reason is the same every time, and it's the crux:

**Schönhage–Strassen (what GMP uses).** SSA works in `ℤ/(2ᴹ+1)` where twiddles are
*shifts* — zero multiplies in the transform. We have it; it's correct. But each
coefficient is a **multi-limb residue** (36–72 limbs), so the butterfly moves ~`W`
words of data where the gold NTT moves **one**. The transform is instruction-bound on
that multi-limb movement (the twiddle shift-spread writes ~`W` limbs/coefficient, and
asm can't help a shift-OR). Even with whole-pass hand-asm carry chains, a tuned SSA lands
**~1.8–2.0× slower than our own gold NTT**. GMP wins with SSA anyway because it neutralizes
that cost with hand-asm `mpn_add_n`, cache-blocking, the √2 trick, optimal ring sizes, and
recursion — decades of metal-level tuning. *Porting GMP's algorithm gives us GMP's algorithm
at our constant factors*, which is below our gold NTT. This is the ceiling.

**Multi-prime NTT + NEON SIMD.** A whole-butterfly 32-bit NTT in 4-lane NEON is genuinely
2.4–3.8× faster *per transform* (the cross-register-file blocker that stops NEON on
64-bit Goldilocks doesn't apply at 32 bits). But a multiply needs 3 transforms and 3
primes + CRT needs 9 — so the per-transform win erodes to break-even.

**IBDWT** (the GIMPS technique for `k·2ⁿ±1`). Validated correct, but its half-length
folding needs `2^(1/L)` in the field, which exists only for small `L` (`ord(2)=192` in
Goldilocks) — so for the engine's large transforms the ~2× fold is field-blocked.

The throughline: **a 1-word prime-field NTT moves the least memory, and on LLVM-compiled
Tungsten that wins.** SSA's "no multiplies" bargain costs ~`W`× the memory, which is the
wrong trade here. Strict single-threaded parity with GMP would require out-engineering
GMP's hand-asm on a representation that is fundamentally heavier for us — so it is not
reachable on this codegen, and the gold NTT (~3×) is the floor.

## Compiler work that came out of it

The multiply effort drove a set of durable compiler fixes and capabilities: a native
i64 ABI for `u64` scalars; fixes to a closure miscompile on `arr[param]` indexing, a
lexer bug where a type-name token used as a variable (`i1`) dropped a following `+`/`<<`,
and machine-int param bindings being lost across branches; carry-chain intrinsics
(`mulhi`/`addcarry`/`subborrow`); an inline-asm capability with raw array pointers; NEON
SIMD builtins (`umull`, Montgomery REDC, modadd/sub); and whole-pass asm NTT-stage
builtins (scalar Goldilocks and 4-lane NEON).

## Lessons (the expensive ones)

- **Validate the convolution, not just the round-trip.** A wrong butterfly sign can give
  a perfect forward→inverse round-trip yet not be a convolution homomorphism — the
  *multiply* silently corrupts. This bit radix-8 twice.
- **A decimal literal ≥ 2⁶³ NaN-box-corrupts on store** in this runtime, which fabricated
  a phantom "asm carry-out bug" and mis-validated several experiments. Build big constants
  via `(0##u64)-x` or shifts.
- **Thermal drift dominates absolute timings.** Always measure candidate vs baseline
  back-to-back, medians of ≥3; if an unrelated baseline moves in lockstep, it's drift.
- Keep field values in `u64[]` arrays — scalar `u64` locals/params for >2⁴⁸ values can
  NaN-box; identifiers split at uppercase letters; `go`/`mul` are reserved.

## Status

The CPU multiply is consolidated into one swept, validated ladder. It is **not yet wired
into Tungsten's core big-int path** (`runtime/runtime.c`'s `bigint_mul_any` is still the
naive O(n²) schoolbook) — that integration is the natural next step so normal Tungsten
bignum code gets the fast path automatically.
