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
