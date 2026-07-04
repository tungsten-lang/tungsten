# Regression: impure ccall wrappers must NOT be memoized.
#
# `fn metal_buffer_read_f32(buffer, i)` forwards a ccall that reads MUTABLE
# Metal buffer memory — it is not pure, so the compiler must not cache its
# result across a write. A slab-AST migration miss had broken the compiler's
# impure-ccall detection (`fn_body_calls_impure_ccall?` gated on the stale
# `type(node) == "Hash"`, which slab nodes report as "Unknown"), so every
# impure ccall `fn` of arity ≤ 2 got memoized and read-after-write returned the
# stale cached value. Fixed by gating on `is_ast_node?` (lowering/types.w).
#
# Compiled-only + macOS 26 (Metal). Prints PASS/FAIL.

use core/metal
device = metal_device()
buf = metal_buffer(device, 16)

metal_buffer_write_f32(buf, 0, ~1.0)
warm = metal_buffer_read_f32(buf, 0)        # would cache read(buf,0)=1 if memoized
metal_buffer_write_f32(buf, 0, ~2.0)        # mutate the same cell
again = metal_buffer_read_f32(buf, 0)       # must observe 2, not the stale 1

<< "warm read   = " + warm.to_s + " (expect 1)"
<< "after write = " + again.to_s + " (expect 2)"
if again == ~2.0
  << "PASS — impure metal_buffer_read_f32 is not memoized across a write."
else
  << "FAIL — read returned a stale memoized value (" + again.to_s + "); impure-ccall detection is broken."
