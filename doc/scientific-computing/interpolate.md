# Interpolation & quadrature

## What other platforms call it

| Platform | Interpolation | Integration |
|----------|---------------|-------------|
| SciPy | `scipy.interpolate` | `scipy.integrate` |
| NumPy | `np.interp` | — |
| MATLAB | `interp1` / `spline` | `integral` / `trapz` |
| Julia | Interpolations.jl | QuadGK.jl |
| R | `approx` / `spline` | `integrate` |

## Tungsten placement options

1. **`core/interpolate`** (chosen) — small surface, both interp + trapz/simpson/quad  
2. `core/integrate` + `core/interpolate` — split like SciPy (more files)  
3. `core/numeric/interp.w` — hide under numeric/  
4. bits only — too fundamental for bits  

```
use core/sci/interpolate
<< Interpolate.linear(xs, ys, x)
spl = Interpolate.spline_natural(xs, ys)
<< Interpolate.spline_eval(spl, x)
<< Interpolate.trapz(ys, dx)
<< Interpolate.quad(-> (x) x * x, ~0.0, ~1.0, 200)
```
