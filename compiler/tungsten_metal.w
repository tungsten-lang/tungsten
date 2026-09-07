# GPU-capable compiler image. Ordinary compile/check/WIRE-run stays lean; a
# program containing @gpu definitions delegates here after its first AST scan.
use lib/compiler_gpu_emitter_metal
use tungsten_driver

# The Metal compiler needs the GPU emitter, not the product runtime surfaces
# used by programs that it compiles.
ccall("w_compiler_image_lean_profile")

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
