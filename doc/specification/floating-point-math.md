# Floating-Point Math Modes

Tungsten compiles floating-point (`f32`/`f64`) arithmetic under one of three
**math modes**. The mode controls which value-changing transformations the
compiler and backend are permitted to apply — fused multiply-add (FMA)
contraction, algebraic reassociation, approximate intrinsics, and denormal
handling. The default is **precise**.

The mode is selected per-compilation by a command-line flag, and can be
overridden for a lexical region of source by the `@strictmath` / `@fastmath`
scoped blocks (§4).

> **Scope note.** Auto-vectorization is permitted in **all** modes — it does not
> change results for the reductions Tungsten vectorizes (it relies on
> `!invariant.load`, not on reassociation). Math mode governs only the
> *value-changing* float transformations listed below.

## 1. The three modes

| Mode | Flag | FMA contraction | Reassoc / algebraic | Approx intrinsics | Denormals | FP exceptions |
|------|------|-----------------|---------------------|-------------------|-----------|---------------|
| **strict**  | `--strict-math` | none (only explicit `fma(a,b,c)`) | no | no | preserved | trapping disabled¹ |
| **precise** *(default)* | *(none)* | direct `a*b ± c` only² | no | no | preserved | trapping disabled |
| **fast**    | `--fast`, `--fast-math` | unrestricted (LLVM `fast`) | yes | yes | flush-to-zero³ | trapping disabled |

¹ Strict controls *contraction and reassociation*; it does **not** re-enable FP
exception trapping. No Tungsten mode traps on `inf`/`nan`/inexact — see §3.
² The contraction carve-out is the defining behavior of precise mode — see §2.
³ Denormal flush-to-zero (FTZ/DAZ) in fast mode is **planned**; see §5.

`--fast-math` is an alias for `--fast` that *additionally* defines the
`FAST_MATH` build-time constant (so `if FAST_MATH` source branches fold to the
fast path). Both forms set the floating-point mode to **fast**.

## 2. Precise mode and the FMA-contraction carve-out

Precise mode contracts a **direct** multiply-add — `a*b + c` or `a*b - c`,
where the addend `c` is **not itself a product** — into a single
`llvm.fmuladd.f64`. This is one hardware FMA: the product `a*b` is kept at full
precision and the result is rounded **once**. This matches C's
`-ffp-contract=on` for these direct patterns.

Precise mode **deliberately differs** from C's `-ffp-contract=on` in one case:
when **both** sides of the add/subtract are products — `a*b ± c*d` — it does
**not** contract. The expression lowers to two independent rounded multiplies
and a bare add/subtract.

> **Why the carve-out.** Contracting `x1*y2 - x2*y1` to
> `fmuladd(x1, y2, -(x2*y1))` rounds `x2*y1` first but keeps `x1*y2` exact
> inside the FMA. For a 2×2 determinant / 2-D cross product where `x1 == x2`
> and `y1 == y2`, the true value is `0`, but the asymmetric rounding yields a
> nonzero residual (~`1e-16`). That is the infamous "FMA broke my cross
> product" sign error. Precise mode refuses it: `a*b - c*d` stays exactly `0`
> when it should. Direct accumulation (`a*b + c`, Horner's method) still gets
> the FMA benefit.

```tungsten
det = x1 * y2 - x2 * y1   # precise: bare fmul/fmul/fsub → exactly 0 when equal
acc = a * b + c           # precise: llvm.fmuladd.f64 (rounds once)
```

If you want full `-ffp-contract=on` behavior (contract `a*b - c*d` too), use
`--fast`, which lets the backend's FMA-formation pass fuse freely.

### 2.1 Explicit `fma(a, b, c)`

`fma(a, b, c)` (three float arguments) computes `a*b + c` as a single fused
multiply-add — the product is kept at full precision and the result is rounded
**once**. It lowers to `llvm.fma.f64`, a hard guarantee of single rounding on
every target (with a soft-float fallback where no hardware FMA exists), exactly
like C's `fma()` from `<math.h>`.

```tungsten
err = fma(x, y, ~0.0 - x * y)   # the exact rounding error of x*y — nonzero
```

`fma` fuses in **every** mode, including strict — it is the *only* way to
obtain an FMA under `--strict-math`, and the explicit way to opt back into
fused precision for a `a*b - c*d` form that precise mode leaves unfused. The
interception applies only when all three arguments are statically float; a
user-defined `fma` over other types dispatches normally.

## 3. FP exception trapping

FP exception trapping (`SIGFPE` on inexact/overflow/invalid) is **disabled in
all modes**, including strict. Tungsten float code never traps; results follow
IEEE 754 default exception handling (quiet NaNs, signed infinities). Strict
mode constrains *contraction and reassociation*, not trapping.

> **Deviation note.** An earlier design called for strict mode to *enable*
> trapping (leaving it disabled only in precise/fast). That is not implemented:
> it would require emitting LLVM `llvm.experimental.constrained.*` intrinsics
> instead of plain `fadd`/`fmul`. Today every mode emits non-constrained
> floating-point operations, so no mode traps. Strict-mode trapping is a
> possible future addition.

## 4. Scoped overrides: `@strictmath` / `@fastmath`

A `@strictmath` or `@fastmath` block overrides the math mode for the
statements it encloses, regardless of the compilation's `--` flag:

```tungsten
@fastmath ->
  total = 0.0
  for x in samples
    total = total + x * weight     # fast: fma + reassoc here
  total

@strictmath ->
  det = a * d - b * c              # strict: never contracts, exact
```

`@strictmath` is useful for A/B-testing a kernel's FMA sensitivity **without
recompiling the whole program** in a different mode: wrap the suspect
computation and compare against the surrounding precise/fast code.

The override applies to the float operations *lexically inside* the block.
Class/constant references inside the block are resolved (autoloaded) normally.

> **Implementation limitation.** A scoped block is a lowering-time construct;
> heap-allocating code placed inside one is not escape-analyzed for early-free
> insertion. The intended use is numeric (`f32`/`f64`) code, where this is a
> no-op. Heavy heap manipulation belongs outside the block.

## 5. Planned fast-mode additions

The following fast-mode behaviors are specified but **not yet implemented**:

- Denormal flush-to-zero (FTZ/DAZ) — `denormal-fp-math=preserve-sign` attribute
  plus a runtime FPCR write at startup.
- Vectorized transcendentals (SLEEF/SVML) for `sin`/`cos`/`exp`/`log`.
- Non-temporal stores (`!nontemporal`) for streaming writes.
- `rsqrt`/`rcp` approximate-reciprocal stdlib intrinsics.

Approximate intrinsics and reciprocal/reassociation licenses are already
carried by the `fast` flag on every float instruction in fast mode.

## 6. Normative vs. implementation-defined

This delineates what a conforming Tungsten implementation **must** guarantee
from what this implementation happens to do.

**Language-spec required (normative):**

- The default mode **must** be value-safe: no reassociation, no approximate
  intrinsics. A bare `a + b` **must** round per IEEE 754 round-to-nearest-even.
- `--strict-math` **must not** introduce any FMA the source did not write
  explicitly via `fma(a, b, c)`.
- An explicit `fma(a, b, c)` **must** compute a fused (round-once) result in
  every mode.
- A `@strictmath` / `@fastmath` block **must** override the ambient mode for
  the float operations it encloses.
- `--fast` / `--fast-math` permit (but do not require any particular)
  value-changing optimization; programs **must not** rely on a specific fast
  result.

**Implementation-defined (this compiler):**

- Precise mode contracts *direct* `a*b ± c` to `llvm.fmuladd` but not
  `a*b ± c*d` (§2). The exact set of contracted patterns is implementation
  choice; only the value-safety of the default is normative.
- The mapping of "fast" to LLVM's composite `fast` flag (`contract reassoc nnan
  ninf nsz arcp afn`).
- FP exception trapping is disabled in all modes (§3).
- Denormal handling, vectorized transcendentals, and non-temporal stores in
  fast mode (§5) are unspecified pending implementation.
- Backend FMA *formation* in fast mode (fusing across statements) is delegated
  to LLVM and depends on target ISA.
