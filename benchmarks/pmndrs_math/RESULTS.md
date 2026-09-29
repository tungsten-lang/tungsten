# pmndrs/math A/B results (2026-09-25)

`--release` builds on an M5 Max; `ab.py` medians of 5-9 interleaved reps at
1M iterations. The machine was heavily shared (load 8-35), so
**instructions/op is the primary signal**; wall-clock ratios tracked it
within ~15%. Controls are the real core class or a verbatim copy of its
bodies (see README). Paste-ready bodies: `vec_landing/`, `mat_landing/`,
`quat_landing/`, and the `*Fast` / `Poly*` / `m32c` classes in
`rng_ab.w` / `polygon_ab.w`. Minimized bug repros: `repros/`.

## What works

| Area | Change | instr x | wall x | memory | numerics |
|---|---|---|---|---|---|
| Vec3 | `length_squared` / `length` fixed-width, unboxed | 43 / 47 | 56 / 58 | same | fmuladd, <= 1 ulp |
| Vec3 | `normalize` fixed-width (divide, not reciprocal) | 5.8 | 5.6 | same | bit-identical |
| Vec3 | new `distance` / `distance_squared` vs `(a - b).length` | 7.9 / 7.6 | 9.6 / 8.7 | 149 -> 3.6 MB | 1-2 ulp |
| Vec3 | `dot` / `cross` / `lerp` with `(b[i] ## T)` reads | 3.4 / 3.3 / 2.8 | 3.7 / 3.3 / 3.1 | same | identical |
| Vec3 | new `scale_and_add` vs `a + b * s` | 3.7 | 4.0 | 294 -> 149 MB | identical |
| Vec3 | `reflect` / `project_onto` / `zero?` fixed-width | 5.6 / 5.4 / 31 | 5.7 / 5.4 / 35 | halved | <= 1 ulp |
| Vec3 | `*_into` / `*_mut` (alias-safe, via `set/3`) | 2.8-10 | 3.4-11 | flat 3.6 MB | identical |
| Vec2/Vec4 | same set | 3.6-53 | 4.3-62 | same pattern | same |
| **Particles** | 1000 x 1000 steps, idiomatic source on the new bodies | **1.72** | **1.70** | same | 17 digits |
| **Particles** | same, written with `sub_into` + `scale_mut` + `scale_and_add_mut` | **5.50** | **6.28** | 873 -> 3.6 MB | 3.7e-15 |
| Quaternion | `+` / `-` via a `(Hypercomplex)` / `(Number)` overload pair instead of `scalar_like?` | 4.6 / 4.8 | 5.8 / 4.7 | 565 -> 147 MB | identical |
| Quaternion | `negate` / `conjugate` / `scale` / `dot` / `abs2` fixed-width | 3.3 / 7.1 / 4.4 / 5.9 / 47 | 3-67 | lower | <= 2.3e-16 |
| Quaternion | `normalize` fixed-width | 9.3 | 9.6 | 228 -> 147 MB | 3.1e-16 |
| Quaternion | `*` hoisted + unboxed + overload guard | 5.4 | 5.4 | same | 2.7e-16 |
| Quaternion | `rotate` by q/\|q\| with k = 2/n (no sqrt, no normalized temp) | 14.4 | 15 | 373 -> 147 MB | 9.7e-16 |
| Quaternion | `to_rotation_matrix` Shoemake s = 2/n | 27 | 27 | 421 -> 196 MB | 9.7e-16 |
| Quaternion | `slerp` with norms folded into coefficients, one allocation | 23-31 | 20-36 | 879 -> 75 MB | 5.8e-16 |
| Quaternion | `.from_rotation_matrix` Shoemake (`r = 0.5/root`) + inline normalize | 5.9-6.4 | 6.2 | 373 -> 147 MB | 3.3e-16 |
| Quaternion | `mul_into` / `normalize_into` / `rotate_into` (via `put/N`) | 10.6 / 14.4 / 17.7 | ~11-20 | flat 2.2 MB | identical |
| Mat4 | `transform_point` / `transform_direction` vs `m * Vec4(...)` | 11.3 / 10.9 | 11.5 / 11.2 | 357 -> 147 MB | closer to exact |
| Mat4 | `.compose(t, q, s)` vs `translation * rot4 * scale` | 9.6 | 10.1 | 817 -> 123 MB | normwise <= 1.22 eps |
| Mat4 | `*/1(Vec4)` / Mat3 `*/1(Vec3)` with `## T` reads | 5.1 / 3.4 | 5.1 / 3.3 | same | <= 8 ulp (fma) |
| Mat4/3/2 | `inverse` with sign-free term order (avoids boxed unary minus) | 1.54 / 1.31 / 1.17 | 1.23 / 1.20 / 1.15 | same | bit-identical |
| Mat4 | `inverse_into` / `transpose_into` | 2.4 / 2.9 | 3.4 / 4.0 | 244 -> 2.2 MB | bit-identical |
| Mat4 | `mul_into` in pmndrs shape (a in locals, b column-at-a-time; now alias-safe) | 1.38 | 1.62 | flat | bit-identical |
| Mat4 | `*/1(Mat4)` operands in locals | 1.13 | 1.12 | same | bit-identical |
| Mat4 | `affine_inverse` | 1.73 vs today (1.13 vs fixed inverse) | 1.51 | same | <= 1.7 eps normwise |
| StatsRng | typed `## i64` mulberry32 (same sequence) + shared `.mix32` | 18-21 | 31-33 | **2049 -> 2.1 MB** | identical |
| StatsRng | new unbiased `next_int(n)` (Lemire) vs `% n` | 13.5 | 22 | flat | fixes modulo bias |
| Polygon | `double_area` / `signed_area` single pass | 1.7 | 1.65-1.69 | same | identical, stays exact |
| Polygon | `contains?` one pass (boundary + crossing) | 2.8-2.9 | 2.7-2.9 | same | 0 mismatches / 12k queries |
| Polygon | `convex?` single pass | 2.1-4.4 | 2.0-4.3 | same | identical |
| Polygon | `convex_hull` octagon prefilter (Akl-Toussaint) | 3.1-6.1 | 3.3-7.3 | same | identical on 26 sets |

## Neutral or worse

| Change | Result | Why |
|---|---|---|
| Reciprocal instead of divide (Mat inverse, Vec/Quat normalize) | NEUTRAL, costs up to 1 ulp | M5 hides the fdivs even in a dependent chain; keep correctly rounded divides |
| Mat3 determinant pmndrs form | NEUTRAL | core already shares the cofactors |
| Vec3 `<=>` override | WORSE than keeping the generic body | the fixed `length_squared` makes the generic `<=>` faster (6.3x) |
| Quaternion same-class typed overload `*/1(Quaternion)` | WORSE: unsound | `Quaternion<f64> * Quaternion<f32>` reads garbage |
| Quaternion `rotate_unit` / `slerp_unit` (pmndrs unit assumption) | NEUTRAL: 5-10% | changes results for non-unit input; opt-in only |
| pmndrs `fromMat3` without normalize | NEUTRAL: 4% | 0.4-0.7% off on drifted matrices |
| exact quickhull2 | WORSE | O(n^2) worst case, 2.7 GB on 60 BigInt points |
| xorshift64 / splitmix64 instead of mulberry32 | NEUTRAL vs typed mulberry32 | changes the pinned sequence |
| Boxed-read fixed-width bodies (pmndrs shape alone) | 1.07-1.8x only | the win comes from unboxing the operand |

## Root causes found (compiler/runtime; unfixed)

1. Reading another object's typed field (`@1.components[i]`) is a dynamic
   `[]` call returning a boxed float, and boxed `w_add`/`w_mul` walk ~15 type
   arms (decimal, currency, percent, quantity, ...) before the double arm.
   Most wins above are `(x ## T)` workarounds for this; a both-doubles fast
   arm first, or a class-guarded typed read when `@1`'s class matches self's,
   would speed up all of them at once.
2. `-x` on a typed float and `2 * typed_float` lower to boxed runtime calls.
3. `(Vec4)` / `(Vector)` / `(Vec3<T>)` parameter annotations do not type the
   argument (and `(Vec3<T>)` returns the class instead of running the body).
4. A typed same-class parameter's slow path still does T-typed loads, so
   mixed-T operands read wrong memory: **`Mat3<f64> * Mat3<f32>` in core
   today returns denormals/NaN** (memory-safety bug).
5. A subclass that defines one overload of an operator drops the inherited
   overload set; an untyped overload after a typed one replaces it.
6. Subclasses must re-declare `- data` or their bodies run boxed.
7. f32 specialisation: `a0 = a[0]` then arithmetic emits invalid IR.
8. `respond_to?(:sym)` is false where `respond_to?("str")` is true.
9. Array-literal lowering stores each element immediately, blocking load reuse.
10. Compiled `is_a?(Array)` costs ~1.6 us (360x a class-name compare).
11. `Polygon.signed_area`/`area`/`pick_area` fail on BigInt/Rational input
    (`* 0.5`); blockless `Array#sort` orders Rationals as strings.
12. StatsRng boxes and promotes to BigInt every draw (~1 KB leaked per
    number); it is missing from the autoload table.
13. Allocated Vec/Mat/Quaternion values are never reclaimed (147-244 B each),
    which is why every `*_into` form wins on memory by 40-400x.
