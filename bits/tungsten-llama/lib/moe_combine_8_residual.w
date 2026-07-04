# Fused MoE combine + residual: x[i] += Σ_k weights[k] * eo[k][i].
# Replaces the moe_combine_8 → residual_add pair (two dispatches per
# layer, 96/token) with one kernel that reads x, accumulates the
# weighted expert sum into a register, and writes back.
#
# Same structure as moe_combine_8 but skips the intermediate ffn_out
# buffer entirely — accumulator goes straight into x.

## f32[]: x
## f32[]: eo0
## f32[]: eo1
## f32[]: eo2
## f32[]: eo3
## f32[]: eo4
## f32[]: eo5
## f32[]: eo6
## f32[]: eo7
## f32[]: weights
## i32: n_rows
@gpu fn moe_combine_8_residual(x, eo0, eo1, eo2, eo3, eo4, eo5, eo6, eo7, weights, n_rows)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n_rows
    accum = x[i] ## f32
    accum = accum + weights[0] * eo0[i]
    accum = accum + weights[1] * eo1[i]
    accum = accum + weights[2] * eo2[i]
    accum = accum + weights[3] * eo3[i]
    accum = accum + weights[4] * eo4[i]
    accum = accum + weights[5] * eo5[i]
    accum = accum + weights[6] * eo6[i]
    accum = accum + weights[7] * eo7[i]
    x[i] = accum
