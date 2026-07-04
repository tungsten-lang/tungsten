# Fused SiLU(gate) * up — the activation half of a SwiGLU FFN.
#
# silu(x) = x * sigmoid(x) = x / (1 + exp(-x))
# out[i] = silu(gate[i]) * up[i]
#
# One thread per element. Bounds-checked so dispatch_n can over-pad.

## f32[]: gate
## f32[]: up
## f32[]: out
## i32: n
@gpu fn silu_mul(gate, up, out, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    g = gate[i] ## f32
    sig = ~1.0 / (~1.0 + exp(~0.0 - g)) ## f32
    out[i] = g * sig * up[i]
