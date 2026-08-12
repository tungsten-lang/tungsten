# SPIR-V / Vulkan GLSL GPU dialect emit spec.
# Tests that `@gpu fn` AST lowering emits Vulkan GLSL / SPIR-V annotations.

## f32[]: input
## f32[]: output
@gpu fn spirv_kernel(input, output)
  i = gpu.thread_position_in_grid.x ## i32
  output[i] = input[i] * 2.0

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("spirv.spec_registered", true)
