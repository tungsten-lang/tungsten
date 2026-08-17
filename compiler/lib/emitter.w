# Emitter — renders WIRE IR to LLVM IR text
# Takes a WIRE module (from lowering) and produces a complete .ll file.

use runtime_types
use wire
use hashing
# LLVM name transliteration (llvm_safe_name) — shared with lowering via
# its own module so `use lib/emitter` STANDALONE (the emitter unit specs)
# is a complete program instead of fabricating dangling `__w_*` symbols
# that only die at link time.
use naming

use emitter/primitives
use emitter/analysis
use emitter/artifact
use emitter/numeric_instructions
use emitter/runtime_instructions
use emitter/instructions
use emitter/parallel
