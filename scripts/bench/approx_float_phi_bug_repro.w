# Regression: approx-Float phi merge (fixed in the lowering var-type guard).
#
# A not-taken conditional that assigns an approx-Float LITERAL (`~X`) to a
# variable already holding a BOXED Float used to corrupt the value (2.0 -> 2.125,
# in the NaN-box tag bits): the assign retyped the local to machine-float so
# reads emitted `load double` over the boxed-i64 slot. Fixed by extending the
# existing "don't retype a materialized boxed local" guard (integers only) to
# also cover machine-floats in compiler/lib/lowering.w.
#
# Prints PASS when correct. Run compiled (-o) on macOS 26.

use core/metal
device = metal_device()
buf = metal_buffer(device, 8)
metal_buffer_write_f32(buf, 0, ~2.0)

v = metal_buffer_read_f32(buf, 0)   # runtime Float = 2.0
if v < ~0.0                          # false — branch NOT taken
  v = ~0.0                           # approx-Float literal
# v must still be 2.0
<< "v after not-taken `v = ~0.0` = " + v.to_s + " (expect 2)"
if v == ~2.0
  << "PASS — approx-Float phi merge is correct"
else
  << "FAIL — not-taken conditional assigning an approx-Float literal corrupts the Float"
