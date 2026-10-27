# Articles

Write-ups from building a matrix-multiplication rank search natively in Tungsten.

The work started from a question — could a self-verifying, all-paths search idea
(originally for the Traveling Salesman Problem) be turned on the problem of
*discovering* faster matrix-multiplication algorithms? — and ended as a fast,
leak-free, SOTA-matching flip-graph search written entirely in Tungsten, plus a
set of hard-won compiler-performance lessons.

## Contents

- **[matmul-flip-graph-search.md](matmul-flip-graph-search.md)** — the search
  itself: the flip-graph method over GF(2), the native-Tungsten implementation,
  and the results (3×3 → 23, 4×4 → 47, 5×5 → 95). What was matched, what wasn't,
  and how those results compare with the current GF(2) record targets.

- **[tungsten-performance-engineering.md](tungsten-performance-engineering.md)** —
  the engineering: a root-caused compiler codegen bug, a 375 MB/s memory leak, and
  a profiler-guided **18× speedup** — with the general rule that came out of it
  (*type hot-loop variables `## i64`; profile, don't guess*).

- **[metaflip-certified-bounds-and-block-composition.md](metaflip-certified-bounds-and-block-composition.md)** —
  the next research phase: an independent replay of the new 3×3 lower bound 20,
  an independently replayed quotient-rank proof that `<3,2,4>` has exact GF(2)
  rank 20, 186 independently reconstructed
  block-composed GF(2) algorithms (176 strict apparent records, one co-record,
  and nine exact upper bounds without a pinned GF(2) comparator), the candidate 7×7
  rank-247 record, and exact tunnels into term-disjoint restart basins.

### Compiler, Runtime & Bignum Engineering

- **[bignum-engine.md](bignum-engine.md)** — how the C runtime's `WValue`
  arbitrary-precision integer engine went from trailing GMP to winning 470+ of
  485 benchmark cells against GMP 6.3's `mpz_*` API on Apple M5 Max.
- **[bignum-multiply.md](bignum-multiply.md)** — building a fast arbitrary-precision
  multiply natively in Tungsten (Goldilocks NTT + Karatsuba), taking modular
  squarings from 118× to ~3× of GMP.
- **[compiler-and-runtime-optimization-campaign.md](compiler-and-runtime-optimization-campaign.md)** —
  profile-guided optimization across the C runtime, `core/`, and the self-hosted
  WIRE compiler pipeline.
- **[stdlib-and-runtime-performance-campaign.md](stdlib-and-runtime-performance-campaign.md)** —
  engineering and cross-language benchmarks across JSON/CSV/Base64/UTF-8, regex,
  radix sort, work-stealing channels, and linear algebra against C, Rust, Go, and Java.
- **[slab-ast-design.md](slab-ast-design.md)** — replacing heap-allocated hash AST
  nodes in the self-hosted compiler with a one-word-per-node arena-and-handle
  Slab AST.
- **[lto-target-features-mismatch.md](lto-target-features-mismatch.md)** — root-causing
  an 18% LTO performance regression to a missing `target-features` attribute across
  `-march=native` boundaries.

### SIMD, Lexing & Apple Silicon Hardware

- **[json-lexer-perf-ladder.md](json-lexer-perf-ladder.md)** — pushing a self-hosted
  JSON lexer from 1.4 GB/s to 21 GB/s (2.57 billion tokens/sec) across 32 threads.
- **[simd-classifier-from-scratch.md](simd-classifier-from-scratch.md)** — building a
  4.7 GB/s simdjson-class structural classifier in 200 lines of C.
- **[shrn-xtn-apple-silicon.md](shrn-xtn-apple-silicon.md)** — why NEON `shrn`/`xtn`
  bitmap tail compression loses to vector-domain lane reduction on Apple Silicon.
- **[lightning-1-7b-passing-mlx.md](lightning-1-7b-passing-mlx.md)** — taking pure-Tungsten
  Lightning-1.7B NVFP4 decode from 0.71× to 1.16× MLX (240 tok/s).
- **[metal4-matmul2d-on-m5-max.md](metal4-matmul2d-on-m5-max.md)** — wiring Metal 4's
  cooperative-tensor `mpp::tensor_ops::matmul2d` into the runtime on M5 Max.
- **[sme-sme2-on-apple-silicon.md](sme-sme2-on-apple-silicon.md)** — probing ARM
  SME / SME2 and LUTI4 on Apple Silicon for quantized LLM inference.

## Project summary

A flip-graph matrix-multiplication search (flips + reductions + plus-transitions,
all over GF(2)) was implemented as native compiled Tungsten, including the *full*
Arai et al. adaptive policy (structured plus-transition + edge-constraint
hierarchy). Getting it fast and correct required fixing a compiler codegen bug,
killing a per-move bignum leak that OOM'd the machine in ~20 s, and an 18×
profiler-guided speedup (the default arbitrary-precision `Int` was routing every
hot-loop compare/add through bignum helpers). The finished search runs leak-free at
~10–28 million moves/second per core and matches standing records: **3×3 rank 23**
and **4×4 rank 47** (the latter now reached in ~1 minute from naive via the edge
hierarchy, a verified decomposition disjoint from AlphaTensor's). It does **not**
break any record: **5×5 walls at 95** (not 94) under every policy tried, and **6×6
stalls at the recursive seed 161** because the Kronecker seed is a near-isolated
flip-graph vertex. Current larger GF(2) targets are lower still: 5×5 rank 93, 6×6
rank 153, and 7×7 rank 247. That first search phase broke no record; its durable wins were the
compiler fixes, the 18× speedup, the edge-constraint convergence on small sizes,
and an honest map of exactly where the method's reach ends.

The follow-up work changes that last conclusion in two carefully separated
ways. Wang's certificate now proves the stronger 3×3 lower bound 20, while
support-aware block composition gives 176 strict apparent GF(2) upper-bound records
across larger rectangular formats and a weighted outer construction gives a
candidate 7×7 rank-247 record. For `<3,2,4>`, two constrained mode lemmas and
six independently replayed quotient-rank pseudo-Boolean proofs now exclude
rank 19, closing the global GF(2) rank at exactly 20. A hardened two-basin 4×4 campaign
still did not find rank 46 after 988.5 billion reported moves; that remains a
search negative, not a lower-bound proof. The third article above gives the
exact certificates, audit boundaries, and reproduction details.
