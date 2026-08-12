## f32[]: output
@gpu fn missing_input_hint(input, output)
  output[0] = input[0]

## f32[]: output
@gpu fn unsupported_expression(output)
  output[0] = unknown_gpu_primitive(1.0)

## f32[]: input
## f32[]: output
@gpu fn cuda_reduction_error(input, output)
  value = input[0] ## f32
  output[0] = tg_sum(value)
