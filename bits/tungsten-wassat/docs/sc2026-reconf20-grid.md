# A move-three obstruction in reconf20_50_grid10_1_6141

The original DIMACS has 139,160 variables and 548,063 clauses. Its first 180 negative binary clauses are the edges of the 10×10 grid in row-major order. The same edges recur at each of 49 time layers. Each layer selects exactly one vertex to remove and one to add. Two coordinate selectors per vertex implement the at-most-one constraints. A token can jump to any empty cell provided the resulting occupied set is independent. The start is fixed in the first transition, and 100 units fix the end. Another 1,225 disjunctions each require a difference between one pair of the 50 configurations.

The start and goal each occupy 48 squares of opposite checkerboard colors. For each of the 1,128 goal pairs, count distinct initially occupied neighbors of either vertex. The minimum is four. The full histogram is 24 pairs with four neighbors, 102 with five, 310 with six, 458 with seven, and 234 with eight. Occupying both vertices by move three requires all their initial neighbors to have left. Three removal slots cannot vacate four distinct squares. Thus at most one goal can be occupied at move three. The last 46 moves can fill at most 46 more, short of the required 48. This contradiction already applies when repeated states are allowed.

## Solver and checkers

Wassat recovers the graph, endpoints and horizon from the formula. It chooses a cut leaving two more goal vertices than remaining moves, looks for enough blocking neighbors for every goal pair, and authenticates the removal and addition frame clauses and the selector implications and exclusions used in the argument. The search currently admits cuts at moves one through four and up to 56 goal vertices. On a miss it returns to normal solving. The ordinary file and stdout DRAT paths emit identical certificates. The final part uses extended resolution to reduce the 48-pigeon, 47-slot contradiction one pigeon at a time.

Median of three local release runs was 0.085 s in fast mode and 0.366 s including file DRAT generation. The native certificate has 1,352,944 lines and 29,397,490 bytes. Forward DSR checking took 7.68 s including parsing. Independent LSR replay took 1.11 s. VeriPB 3.0.2 checked a separate cutting-planes proof in 0.27 s. A modified endpoint with a concrete 49-jump path passed full original-clause model checking on the modified input. The cut declined that instance and a separate mutation missing the first removal frame for vertex 1.

The [replay bundle](../../../build/sc2026-reconf-grid/checked-reconf20.tar.gz) contains the original CNF, both certificates, checker logs, hashes and commands. The [release candidate](../../../build/sc2026-reconf-grid/wassat) was built in an isolated source copy using HEAD versions of cnf.w, policy.w, portfolio.w and solver.w on both sides of the comparison. At qualification time the full dirty checkout failed to compile at the i32 length argument to wassat_hdr_put in solver.w.

## Baseline profile

File-DRAT mode bypassed the existing fast path search for reconfiguration graphs. Of 5,403 main-thread samples, 3,778 were in watched propagation (69.9%), 757 in conflict analysis (14.0%), and 383 in backjumping (7.1%). Parsing took 13 ms. Implication rewriting took 238 ms, subsumption 424 ms, and none of the 4,600 AND2 candidates was eliminated. The interrupted run wrote 1,043,173,125 bytes of partial DRAT. [CPU sample](../../../build/sc2026-reconf-grid/window.sample) · [Stage log](../../../build/sc2026-reconf-grid/window.log)

## Cross-family controls

Eight SAT controls ran three times each with the cut enabled and disabled in the same candidate binary. All 48 models passed clause checking. Median milliseconds were as follows. [Paired measurements](../../../build/sc2026-reconf-grid/paired.jsonl)

| Control | Cut disabled | Cut enabled |
|---|---:|---:|
| Circuit_multiplier36 | 12.1 | 10.4 |
| st_540_25_12_12_9.af | 8.1 | 8.4 |
| sted5_0x1e3-20 | 20.8 | 21.0 |
| knight_18 | 149.0 | 148.0 |
| sum_of_3_cubes_50_bits_91 | 28.1 | 24.0 |
| n384p5q2_vh.af_138 | 1949.2 | 1905.1 |
| cabp-P-can__445.mtx.rnd-k96 | 343.2 | 309.6 |
| stable-400-0.1-7 | 1167.1 | 1190.3 |

The extended controls ran once per release, with solver time below in seconds. Independent checkers accepted all eight DRAT proofs and four SAT models. These single runs overlapped with other host activity. [Baseline](../../../build/sc2026-reconf-grid/extended-baseline.jsonl) · [Candidate and three-second controls](../../../build/sc2026-reconf-grid/controls.jsonl)

| Control | Baseline | Candidate |
|---|---:|---:|
| goldb-heqc-k2mul | 0.28 | 0.16 |
| sqrt-mitern168 | 8.37 | 7.36 |
| WS_500 | 9.65 | 9.58 |
| stable-400 | 1.36 | 2.14 |
| SCPC-500-19 | 27.32 | 29.28 |
| vdwb_k5_n260 | 23.29 | 23.51 |

The six SBDP cases and j3037 all reached the three-second file-DRAT cap in both arms. The candidate separately regenerated all six SBDP circuit certificates byte-for-byte against their previously checked copies.
