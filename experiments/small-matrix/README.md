# Small fixed matrix outputs (item 17)

Mat2/3/4 now expose `a.add_into(b, out)` and `a.sub_into(b, out)`, writing
caller-owned storage and returning `out`. Mat2 also gains `mul_into`, matching
Mat3/4. Addition/subtraction allow exact input/output aliases; partially
overlapping views are outside the contract. Product output must not overlap
an input. Ordinary operators retain fresh-result semantics.

`python3 scripts/test-small-matrix.py` checks nontrivial products, source/result
independence, exact componentwise aliases and returned destination identity.
It measures six alternating pairs of 50,000 f64 additions per size, changing
one input each iteration and checking the final value. Compilation uses
release/no-LTO; timings cover the native loop including the method calls and
input update, not compilation/process startup. Raw pairs are in `result.json`.

These measurements compare two explicit ownership contracts, not a speedup to
ordinary `+`. Reusable output removes result-allocation requests from the
source loop; this test does not measure global allocator counts. This machine
was not reserved, so ratios are local directional evidence.
