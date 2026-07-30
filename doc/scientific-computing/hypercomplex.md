# Hypercomplex wedge

Tungsten's tower is rare in production languages:

| Type | Path | Use |
|------|------|-----|
| Complex | `numeric/hypercomplex/complex` | signals, QM amplitudes |
| Quaternion | `…/quaternion` + `quaternion_metal` | attitude, robotics, 3-D rotations |
| Octonion | `…/octonion` | theoretical physics, fun |
| Sedenion… | higher Cayley–Dickson | research / education |

## Packaging as a product

1. **Docs first** (this file + getting-started examples).  
2. **GPU path**: keep `QuaternionMetal` hot for SLAM / game-style workloads.  
3. **Interop**: convert `Complex` ↔ FFT split arrays (`FFT` uses re/im lists).  
4. **Benchmarks**: rotate 10⁷ quaternions CPU vs Metal (qjulia already exists
   under `benchmarks/qjulia/`).  
5. **Narrative**: “pseudocode for geometric algebra” — not “another NumPy”.

Do not hide the tower in a bit: it is a **language identity** feature.
Ensure autoload rows stay registered in `core/tungsten.w`.

## Complex analysis

`Complex<T>` has polar constructors and principal elementary functions:

```w
i = Complex<f64>.i
z = Complex<f64>.polar(~2.0, ~0.7)

z.exp
z.log
z.sqrt
z.sin
z.cos
z.tan
z.sinh
z.cosh
z.tanh
z.asin
z.acos
z.atan
z.asinh
z.acosh
z.atanh
z.pow(~0.5)
```

`**` remains exact integer exponentiation by squaring; `pow` is the principal
complex power `exp(exponent * log(z))`. Branch-sensitive functions use the
principal logarithm with argument in `(−π, π]`.

`Calculus.integrate` accepts complex-valued integrands and reports a real norm
for its error estimate. Taylor jets and multivariate differentials support the
same real elementary-function names, so analytic formulas need minimal changes
when moving between evaluation modes.
