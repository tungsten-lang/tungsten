# Reduce 8 per-slot expert outputs into ffn_out, weighted by router
# weights — single dispatch over all 8 slots. Replaces the 8-dispatch
# wadd phase + its inter-dispatch synchronization.
#
# Hardcoded for TOP_K=8 because Tungsten @gpu has fixed parameter
# arity. Caller passes 8 separate per-slot down outputs and a packed
# 8-element weights buffer.

## f32[]: eo0
## f32[]: eo1
## f32[]: eo2
## f32[]: eo3
## f32[]: eo4
## f32[]: eo5
## f32[]: eo6
## f32[]: eo7
## f32[]: weights
## f32[]: ffn_out
## i32: n_rows
@gpu fn moe_combine_8(eo0, eo1, eo2, eo3, eo4, eo5, eo6, eo7, weights, ffn_out, n_rows)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n_rows
    accum = weights[0] * eo0[i] ## f32
    accum = accum + weights[1] * eo1[i]
    accum = accum + weights[2] * eo2[i]
    accum = accum + weights[3] * eo3[i]
    accum = accum + weights[4] * eo4[i]
    accum = accum + weights[5] * eo5[i]
    accum = accum + weights[6] * eo6[i]
    accum = accum + weights[7] * eo7[i]
    ffn_out[i] = accum
