# Exact-gate equivalence and reuse coverage for caller-owned parity slabs.
# The same scratch object is deliberately reused after both exact and inexact
# results; this is the allocation-free path used by long-lived coordinators.

use ../lib/metaflip/rect

failures = 0 ## i64

-> verify_scratch_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

failures += verify_scratch_expect("2x2 scratch words", ffw_verify_scratch_words(2, 2, 2) == 1)
failures += verify_scratch_expect("2x2x5 scratch words", ffw_verify_scratch_words(2, 2, 5) == 7)
failures += verify_scratch_expect("7x7 scratch words", ffw_verify_scratch_words(7, 7, 7) == 1839)

# Square current/best views agree with the compatibility API.
n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
square = i64[ffw_state_size(capacity)]
rank = ffw_init_naive_cap(square, n, capacity, 71001, 0, 1, 1, 1) ## i64
words = ffw_verify_scratch_words(n, n, n) ## i64
scratch = i64[words]
scratch[0] = 0 - 1
failures += verify_scratch_expect("square naive rank", rank == 8)
failures += verify_scratch_expect("square current reusable exact", ffw_verify_current_exact_scratch(square, n, scratch, words) == ffw_verify_current_exact(square, n))
failures += verify_scratch_expect("square best reusable exact", ffw_verify_best_exact_scratch(square, n, scratch, words) == ffw_verify_best_exact(square, n))

# Leave a real syndrome in scratch, repair the view, and prove the following
# call clears that residue rather than inheriting a false mismatch.
square_best_u = square[47] ## i64
saved_square_u = square[square_best_u] ## i64
square[square_best_u] = saved_square_u ^ 2
square_old_error = ffw_best_exact_error(square, n) ## i64
square_scratch_error = ffw_best_exact_error_scratch(square, n, scratch, words) ## i64
failures += verify_scratch_expect("square corrupt error equivalence", square_old_error > 0 && square_scratch_error == square_old_error)
square[square_best_u] = saved_square_u
failures += verify_scratch_expect("square reuse after mismatch", ffw_verify_best_exact_scratch(square, n, scratch, words) == 1)

scratch[0] = 123
short_error = ffw_best_exact_error_scratch(square, n, scratch, 0) ## i64
failures += verify_scratch_expect("square undersized scratch fails closed", short_error == 0 - 20 && scratch[0] == 123)

# Exercise repeated calls through one slab.  Any allocation in this loop is a
# regression in the explicit-scratch verifier rather than part of its API.
i = 0 ## i64
reused = 0 ## i64
while i < 256
  reused += ffw_verify_best_exact_scratch(square, n, scratch, words)
  i += 1
failures += verify_scratch_expect("square repeated reuse", reused == 256)

# Rectangular views use the same generic support slab and preserve identical
# first-mismatch diagnostics.
rn = 2 ## i64
rm = 2 ## i64
rp = 5 ## i64
rcapacity = ffr_default_capacity(rn, rm, rp) ## i64
rect = i64[ffr_state_size(rcapacity)]
rrank = ffr_init_naive_cap(rect, rn, rm, rp, rcapacity, 72001, 0, 1, 1, 1) ## i64
rwords = ffw_verify_scratch_words(rn, rm, rp) ## i64
rscratch = i64[rwords]
ri = 0 ## i64
while ri < rwords
  rscratch[ri] = 0 - 1
  ri += 1
failures += verify_scratch_expect("rect naive rank", rrank == 20)
failures += verify_scratch_expect("rect current reusable exact", ffr_verify_current_exact_scratch(rect, rn, rm, rp, rscratch, rwords) == ffr_verify_current_exact(rect, rn, rm, rp))
failures += verify_scratch_expect("rect best reusable exact", ffr_verify_best_exact_scratch(rect, rn, rm, rp, rscratch, rwords) == ffr_verify_best_exact(rect, rn, rm, rp))

rect_best_v = rect[48] ## i64
saved_rect_v = rect[rect_best_v] ## i64
rect[rect_best_v] = saved_rect_v ^ 2
rect_old_error = ffr_view_error(rect, rect[47], rect[48], rect[49], 0 - 1, rect[7], rn, rm, rp) ## i64
rect_scratch_error = ffr_view_error_scratch(rect, rect[47], rect[48], rect[49], 0 - 1, rect[7], rn, rm, rp, rscratch, rwords) ## i64
failures += verify_scratch_expect("rect corrupt error equivalence", rect_old_error > 0 && rect_scratch_error == rect_old_error)
rect[rect_best_v] = saved_rect_v
failures += verify_scratch_expect("rect reuse after mismatch", ffr_verify_best_exact_scratch(rect, rn, rm, rp, rscratch, rwords) == 1)
failures += verify_scratch_expect("rect undersized scratch fails closed", ffr_view_error_scratch(rect, rect[47], rect[48], rect[49], 0 - 1, rect[7], rn, rm, rp, rscratch, rwords - 1) == 0 - 20)

if failures > 0
  << "verify scratch: " + failures.to_s() + " failure(s)"
  exit(1)

<< "verify scratch: ok"
