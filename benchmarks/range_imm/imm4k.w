# Immediate-Range twin of arr.w via the raw runtime funnel (ccall).
#
# Since producers landed, arr.w's own `lo..hi` mints the immediate form —
# so arr before/after IS the end-to-end story. This file keeps the ccall
# construction path covered, and doubles as the regression proof for the
# analysis.w rule that plain-ccall args pin their locals boxed (the
# computed `lo`/`hi` below once arrived as raw promoted bits and the
# funnel's w_is_int guard rejected them).

use ../../core/range

fn work(iters, len)
  cells = [0, 0, 0, 0, 0, 0, 0, 0]
  total = 0
  i = 0
  while i < iters
    lo = i % 1000
    hi = lo + len
    cells[i & 7] = ccall("w_range_imm_try_w", lo, hi, false)
    r = cells[i & 7]
    total = total + r.first + r.last + r.size
    if r.include?(lo + 32)
      total = total + 1
    total = total + r.sum
    i += 1
  total

<< work(40000, 4096)
