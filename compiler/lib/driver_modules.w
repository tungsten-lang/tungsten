# Shared module graph for compiler entry points (tungsten, tungsten_metal, repl).
# Loading this prefix first gives every compiler image the same core + library
# declaration order before image-specific extensions and driver execution.
use core/integer
use core/numeric/int
use core/numeric/float
use core/numeric/big_int
# String/Symbol#size and #length are source methods on the shared 0xF9 facade.
# Keep the self-host registration explicit for stage-0 loaders predating the
# broad dynamic-receiver autoload gate.
use core/string
# The self-host uses StringBuffer pervasively. Keep this explicit so a stage-0
# compiler whose loader predates the constructor-autoload trigger can build the
# first source-size stage after the native IC is removed.
use core/string_buffer
use lexer
use parser
use compiler
use loader
use error_formatter
use return_inference
use compiler_gpu_emitter
use hashing
use optimization_report
use perf_inspect
use driver/ir
use driver/shard_codegen
use driver/link
use driver/pipeline
