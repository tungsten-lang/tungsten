# Interval / rigorous numerics

## Why

Most languages only have IEEE floats. Tungsten already had interval
types; we productize them as a **verification wedge**:

- range enclosures for expressions
- branch-and-bound global optimization
- validated roots (interval Newton later)
- teaching numerical analysis

## How

`core/numeric/interval.w` — `Interval` with lo/hi endpoints:

```
use core/numeric/interval   # or autoload Interval
a = Interval.new(~1.0, ~2.0)
b = Interval.new(~-0.5, ~0.5)
<< (a + b).to_s     # [0.5, 2.5]
<< (a * b).to_s
```

v0 uses plain f64 endpoints (not directed rounding). Next steps:

1. outward rounding mode (fesetround) in a tiny C helper  
2. interval Newton in `Optim`  
3. interval-aware ODE step  
4. docs + examples in `spec/sci/interval_spec.w`

`IntervalF64` remains the specialized subclass hook.
