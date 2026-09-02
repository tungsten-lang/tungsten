# Bench log (cold single-shot, b40 subset, stream 7, budgets 600M/1.5G)
| item | binary | score | wall | verdict |
|---|---|---|---|---|
| baseline | md_order60 | 0.7533 [0.7959 0.7948 0.6901] | 889s | — |
| #12 CSR block extraction + #13 scratch reuse | md_order61 | 0.7533 (identical) | 759s (-15%) | ADOPT |
| #16 early bound + #17 branchless + #18 dup-prune (batch) | md_order62 | 0.7571 (+0.0039, mpbp_35 +33%) | 849s (-5%) | REJECT batch → bisect |
| #7 rgsub gate n>1500 + scaled band | md_order63 | -0.0073 vs t16_18 (ringpack_20_3 -25%, chimera -1%) 5 better/0 worse | +5% | ADOPT |
| #16 early abort bound (bisected) | — | mpbp_35 +33% alone; valid bound, bad trajectory | — | REVERT |
| #2 subtree-scoped anneal (untuned, 200k evals/64 blk) | md_order64 | -0.0015 vs t7 (sppc1pq -6.1%, sppc3pq -1.1%) 5 better/0 worse | +94% | keep, tune cost |
| mainline = 12,13,17,18,7,2 (no 16) | md_order65 | 0.7442 (-0.0090 vs base) 11 better/1 worse | 1658s | — |
| #2 tuned (50k evals, 16 blk) | md_order66 | 0.7449 (-0.0084 vs base) 10 better/1 worse | +66% (overlapped run) | ADOPT |
| #5 segment relocate | md_order67 | +0.0006 vs t2tuned, 5 better/4 worse | — | REJECT |
| #6 macro 2-stream | md_order68 | +0.0000, 0/1 | — | REJECT |
| #9 predcorr gate 60k | md_order69 | +0.0000, 0/0 | — | REJECT |
| #8 terminal repass (realizer rotation) | md_order70 | -0.0000, 2 better/0 worse | — | keep (neutral+) |
| #4 pool crossover | md_order71 | -0.0017 vs t8, 13 better/1 worse | — | ADOPT |
| #3 seed-allocation rule | md_order73 | +0.0011 vs mainline, 2 better/4 worse | — | REJECT |
| #10 FM balance 45/55 | md_order74 | 0.0000 on b40 (grid probe 935k->807k) | — | keep (neutral) |
| #1 fusion + #10 ND fix + empty-block guard | md_order78 | +0.0001 vs mainline, 2 better/5 worse | -0% | neutral: keep (simpler code, grid fix) |
| #15 in-binary 4-thread relabel carrier (deterministic seed-order merge) | md_order79 | identical flops on spot rows | bench queued | — |
| #14 supervariable (indistinguishable-node) compression seeds | md_order80 | — | bench queued | — |
| #11 König exact min vertex cover for ND separators | md_order81 | grid 60x60 2.07M->2.03M, 100x100 9.856M->9.850M | bench queued | — |
| #20 Metal ILS streams | — | feasibility arithmetic: n×words×4B per stream (n=5000: 3MB; 1000 streams = 3GB) — only n≤2000 fits, where we already beat the leader; no bench run | — | DEFER (not worth the port) |
| #15 v1 threaded relabel carrier | md_order79 | +0.0000 (1/1), wall +10% (big rows have 0-3 seeds; per-thread setup cost) | +10% | REJECT → v2 block-parallel rgsub |
| #15 v2 block-parallel rgsub (4 threads, sequential exact accept) | md_order82 | identical flops; mpbp_35 55s->18s, sppc3pq 149s->101s | ~-40% big rows | ADOPT (bench queued) |
| #19 wall sweep (md_order79, b40) | — | x100/x1.0 0.7430@1401s; x200 restarts 0.7412@1451s (-0.0018 for +4%); ILS x2 0.7385@2638s; ILS x0.5 0.7495@883s; x50/x1.5 0.7395@1950s | — | ADOPT restarts x2 (600000/m cap 48); spend v2 savings on ILS x1.5 |
| #14 supervariable compression seeds | md_order80 | +0.0000 (0/0 on 39 rows); crashed 1 tiny dense row (quotient via amd_ordering_of used @pattern.rows) | +8% | REJECT (disabled) |
| #11 König min vertex cover (ND separators) | md_order81 | +0.0000 (0/0 on 39 rows); grid probe 100x100 9.856M->9.850M | +3% | keep (neutral, probe-validated) |
| FULL CORPUS baseline (md_order60, 600M/1.5G, cold) | md_order60 | 0.8350 [lt 0.8935 mid 0.8678 big 0.7666] vs leader 0.8109 | 5732s | — |
| #15 v2 block-parallel rgsub (bench) | md_order82 | -0.0013 (3/1), big-row wall 1100s->774s | -18% | ADOPT (+ flush-leftover fix in md_order84) |
| #15 v2 flush-leftover fix | md_order84 | mpbp_35 1506905->1407477, crudeoil_dt2 +1% (more blocks refined) | — | final binary |
| FULL CORPUS final (md_order84, ILS x1.0, cold) | md_order84 | 0.8301 [lt 0.8939 mid 0.8566 big 0.7624] (-0.0049 vs baseline; 82 better/36 worse) | 7783s (+36%) | — |
| FULL CORPUS final (md_order84, ILS x1.5, cold) | md_order84 | 0.8284 [lt 0.8926 mid 0.8551 big 0.7601] (-0.0067; 94 better/34 worse) | 8638s (+51%) | — |
| Leader (same corpus, same scorer) | — | 0.8109 | — | not reached standalone (no memoization) |

## Cleanup pass (2026-09-02, --release --native, identical flops throughout)
| change | evidence | effect |
|---|---|---|
| window_dp w64 DP sentinel 2^62 -> 2^46 | TUNGSTEN_ALLOC_PROFILE on slay06m: bigint_arena takes 712,356 -> 0 | tiny-row wall -32% |
| exact scorer body -> module-level typed kernel `ssi_counts_kernel` (u32[] ... signature) | ivar-loaded arrays dispatch every read: microbench 41 ms -> 2 ms (20x); `## u32[]` annotation no effect | per-row wall 2.2-3.8x faster (slay06m 3.9 s -> 1.0 s, langford 9.9 -> 3.0, chimera 9.1 -> 4.2) |
| window_state_degree -> typed kernel; window list u32 | same mechanism | included above |
| anneal_refine / order_descent orders typed u32; `flops_for_typed_order` lane (typed perm build) | | slay06m -9%, graphpart-20 -4% |
| whole-suite profile (300 rows @25% budget, macOS sample x3, symbolized via sidemap) | before: counts_under_cached 24.4, rgreedy_refine 23.8, array_slot_load_decoded 14.8, w_method_call_cached 11.0, w_array_get 5.0, w_dispatch_key 3.3, amd_core 3.3, __ulock_wait 2.5, window_state_degree 1.8, nd_ordering_of 1.6 (%) | after: rgreedy_refine 52.0, ssi_counts_kernel 19.2, nd_levelset_of 3.8, array_slot_load_decoded 3.4, amd_core 3.1, __ulock_wait 2.8, w_method_call_cached 2.4, nd_ordering_of 2.0, amf_core 1.6, window_state_degree 1.5 (%) — boxed access + dispatch 34% -> ~7% |
| `.each ->` vs indexed `while` (loop_bench.w) | plain arrays: while 110 ms, each-> 48 ms; typed: while 53/32 ms, times-> 55/44 ms; map-> 36 vs while-push 35 | typed arrays + while stay the hot idiom; each-> only for plain lists |
| rejected: typed copy of the crossover block order | typed read -> boxed pair -> typed store SEGVs (compiler hazard, reproduced twice) | kept plain |
| 300-row allocation census (TUNGSTEN_ALLOC_PROFILE, 25% budget, single process) | bigint_arena 0 / 0 B; array_new 7,776,507 / 119.4 GB; array_aligned 15,964 / 613 MB; array_grow 3,183,192 / 28.0 GB; hash_new 0 | array_new callers (sampled): amd_core 54%, amf_core 15%, nd_ordering_of 7%, telos 5%, counts_under copies 5%, rgreedy 5%; array_grow callers: telos_descent 52%, rgsub 11%, amd_core 6%; aligned: SparsePattern#new 95% (sub-analyses) |
| `## recycle` on the 60 top-scope typed workspaces of amd/amf/window/anneal/descent | build crashed (SIGBUS): recycled typed arrays are not zero-filled and AMD state assumes u32[n] zero-init (probe confirmed) | reverted; recipe = annotate only fully-written buffers or add zero loops |
| clean-build identity | scorer + etree checksums identical between pre-kernel and final sources on 3 orders; per-row flops identical on 4 rows; earlier 16-row divergence was the second session's concurrent uncommitted edits, not the compiler cache |
| b40 clean before/after (pre-kernel vs final, --release --native, 16 workers) | wall lt 837s -> 218s (3.84x), mid 1045s -> 508s (2.06x), big 2243s -> 1425s (1.57x); total -48% | 18/40 rows differ in flops only because the working tree also carries the other session's later arm edits (arm-by-arm trace identical through the last shared arm; final has one extra improving arm) |
