# Interactive compiler image. Keep this entry thin: the ordinary compiler
# excludes the legacy interpreter and REPL, while this wrapper opts into both
# before loading the shared command driver. GPU kernels are not linked in;
# a program with @gpu definitions delegates to the metal image like any
# other compile. This image is a product of `bin/tungsten build`
# (see delegate_compiler_image), so it must stay cheap to rebuild.
use lib/interpreter
use lib/repl
use lib/wit/scenes/date
use tungsten_driver

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
