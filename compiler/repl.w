# Interactive compiler image. Keep this entry thin: the ordinary compiler
# excludes the legacy interpreter and REPL, while this wrapper opts into both
# before loading the shared command driver.
use lib/interpreter
use lib/repl
use lib/compiler_gpu_emitter_metal
use tungsten_driver

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
