# CUDA must reject threadgroup reductions until it has native helpers; emitting
# the MSL __tg_sum_f32 call produces an undeclared symbol in nvcc.

## f32[]: input
## f32[]: output
@gpu fn cuda_tg_reduce_reject(input, output)
  value = input[0] ## f32
  output[0] = tg_sum(value)
