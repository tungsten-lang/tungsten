# Default compiler image. The shared driver contains the normal compile,
# check, batch, and WIRE-run paths; optional product surfaces opt in through
# their own launchers.
use tungsten_driver

# Link-time profile marker. The driver recognizes the emitted call and compiles
# the source runtime without product-only dispatch roots; the no-op itself is
# discarded by full LTO.
ccall("w_compiler_image_lean_profile")

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
