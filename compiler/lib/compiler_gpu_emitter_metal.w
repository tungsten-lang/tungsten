# Full GPU-emitter implementation selected by compiler/tungsten_metal.w and
# compiler/repl.w.

use compiler_gpu_emitter
use metal_emitter

+ MetalCompilerGPUEmitter < CompilerGPUEmitter
  -> available?
    true

  -> collect(ast)
    collect_gpu_kernels(ast)

  -> emit_metal(kernels, only_index = nil)
    emit_gpu_kernels_metal(kernels, only_index)

  -> emit_cuda(kernels, only_index = nil)
    emit_gpu_kernels_cuda(kernels, only_index)

  -> emit_wgsl(kernels, only_index = nil)
    emit_gpu_kernels_wgsl(kernels, only_index)
