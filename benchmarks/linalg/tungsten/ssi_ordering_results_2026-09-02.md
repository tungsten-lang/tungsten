# SSI ordering transfer campaign — 2026-09-02

This campaign evaluated mechanisms from `ssi-ordering-challenge` against
Tungsten's sparse symbolic-analysis implementation.  Candidate timings use
release builds, fresh processes, deterministic graph generators, exact
permutation validation, and the canonical `SparseAnalysis` fill/flop scorer.
Timed samples do not enable allocation profiling; a separate deterministic
run records allocation counts and bytes.

The matched runner is:

```sh
bin/tungsten compile --release --native \
  --out /tmp/ssi-ordering-campaign \
  benchmarks/linalg/tungsten/ssi_ordering_campaign.w
ruby benchmarks/linalg/tungsten/bench_ssi_ordering_campaign.rb \
  --binary /tmp/ssi-ordering-campaign --rounds 7 \
  --case grid:40 --case blocks:22 --case bridge:30 \
  --case articulation:30 --case random:2000 \
  rgsub rgsub_boundary
```

## Retained mechanisms

| Mechanism | Correctness / scope | Matched effect |
|---|---|---|
| Reusable symbolic-score workspace | Public `counts_under` still returns owned buffers; internal scoring reuses fully overwritten typed buffers | Anneal: -2.25% random-80/10k and -2.67% grid-20/3k; allocations 20,069 -> 63 and bytes 12,885,536 -> 81,696 |
| Serialized shared score workspace | A per-analysis mutex protects reused score buffers when callers share one `SparseAnalysis`; RGSUB workers retain private, uncontended analyses | Nine-run RGSUB medians ranged from -0.41% to +0.69%; exact results unchanged; an 8-thread repeated-query regression passed |
| Native exact u32 score reducer | u128 flop sum, u64 fill sum; tested with two `UINT32_MAX` counts and ASan/UBSan | Native pair reduction was 4.5-5.5x faster at 100k counts; narrowing fill to u64 improved it another 40.9% at 100k and 41.9% at 1M |
| Flop-only native reducer | Search loops return the scalar exact objective without allocating `[fill, flops]` | 4.34% faster than the pair reducer at 100k and 5.70% at 1M; end-to-end -0.58% to -6.64% on matched descent/anneal/TELOS/window lanes |
| Immutable typed COO reuse | Analysis-local paths share `@fri/@fci`; public inspection remains owned | AMD -3.58%, MINL -1.56%, window -0.50%, TELOS -9.50%, RGSUB -1.57%, RCM -6.05%, biconnected -8.32% |
| Exact window subset DP | Exhaustive 8! oracle proves the transition objective | Found a 0.61% random-48 flop win; costs 15-50 ms versus about 0.8 ms for the old approximate transition, so it remains small-n/budget gated |
| FIFO AMD tie mode | Deterministic optional policy | Flops: grid-20 -2.27%, blocks-10 -13.40%, bridge-15 -2.59%, random-200 +2.13%; not added to the default portfolio because exact final quality did not improve there |
| Biconnected one-dissection | Iterative Tarjan; exact global scoring decides acceptance | bridge-20 flops -0.844% with +97% candidate time; articulation-12 +5.34% flops; retained as an isolated candidate, not a default arm |
| Pair-only local descent | Deterministic adjacent-swap fixed point | 7-14x faster than perturbing descent at a 3k score budget, but found no quality win; retained as an explicit lane |
| Dense core-lift allocation cap | Refuses the extra dense bitmap above 64 MiB and preserves whole-graph fallback through n=45k | band-24k output identical; peak RSS 1,106,100,224 -> 1,033,732,096 bytes (-69.02 MiB, -6.54%); candidate time 1.414 -> 1.389 s |
| Boundary-aware RGSUB | Subtree vertices are movable; active external neighbors are frozen terminals; exact global rescore gates every splice | See the tables below; 3.23-5.19% flop wins on grid/bridge/blocks, with a hard 3,500/6,000-vertex local bitmap cap |
| Raw-return bitset counts | Typed hot loops call raw-i64 companions for bounded merge/and-not counts, avoiding an Int box/unbox while preserving the boxed helpers | 2.54-4.59x microbenchmark speedup for 4-128-word rows; RGSUB -0.55% to -2.24% across nine shapes, all exact outputs identical |
| Etree-postorder count transform | Postordering only relabels the same filled graph, so parent/count arrays are permuted in O(n) using dead typed buffers instead of rebuilding symbolic analysis | RGSUB setup -8.26% to -15.17% on seven representative shapes (-1.74% shell); three allocations and 120 KB removed at random-5000 |
| Phase-wide CPU-scaled RGSUB workers | Immutable jobs are partitioned across `min(job count, online CPUs, 32)` workers; a conservative estimate caps aggregate dense scratch at 128 MiB; results merge in original order | Versus four-job waves, structured-shape candidate time fell 24-30% from 2.5M through 20M words; random-2000 was neutral; exact results unchanged |
| In-place exact-gated RGSUB splice | The coordinator exclusively owns the order after joining workers; proposals use one reusable block-sized undo buffer and roll back on a non-win | grid-55 -1.97%, blocks-22 -3.61%, random-2000 -0.48%; allocation bytes -3.0%, -7.6%, and -1.0%; 44 shape/stream results identical |
| Typed identity block seeds | Proposal-local identity seeds have a known size and u32 range, so allocate them once as typed storage instead of growing boxed lists | grid-40 -2.31%, grid-55 -3.57%, blocks-22 -3.09%; 61/64 fewer allocations on grid-55/blocks-22; 15-run neutral cases were within +0.11%; 44 shape/stream results identical |
| One-round default RGSUB policy | The normal portfolio runs the concentrated-subtree round once; direct quality lanes retain the macro round | The final portfolio result was identical on six tested shapes; grid-70 -2.71%, bridge-40 -3.16%, articulation-30 -0.79%, other medians within +/-0.5% |
| Watcher MINL lane | Exact four-vertex witnesses wake only affected fill edges; a late exact merge prevents a locally safe watcher result from regressing later portfolio descents | Opt-in `best_watch`: bridge-30 flops -0.100%, random-750 -0.0059%, grid-45 equal; median time +0.92%, -0.29%, +0.98% respectively |
| Bounded SciIO header reads | `File.read_prefix` replaces whole-file reads for format probes | 128 MiB fixture: generic prefix 17.34 ms -> 14.39 us (~1,205x), Parquet metadata 21.13 ms -> 13.16 us (~1,606x), MAT metadata 21.04 ms -> 20.65 us (~1,019x); one-shot peak RSS about 271 -> 2.9 MB |

## Boundary-aware RGSUB

The old local model scored only the original induced graph on an elimination-
tree subtree.  The new lane appends every still-live original neighbor as a
passive terminal.  Terminals contribute to degrees and fill, but cannot enter
the pivot buckets, be selected by simplicial propagation, or escape into the
returned prefix.  A five-vertex regression fixture proves the distinction:
the subtree-only objective prefers identity, while the correct boundary cost
is 41 for identity and 34 for `[2,0,1]`; the full global costs are 46 and 39.

Seven fresh-process alternating samples, 20M word-operation budget:

| Shape | Old median | Boundary median | Old flops | Boundary flops | Flop delta |
|---|---:|---:|---:|---:|---:|
| grid-40 | 98.80 ms | 116.62 ms | 517,207 | 493,888 | -4.51% |
| blocks-22 | 184.51 ms | 200.70 ms | 273,232 | 262,804 | -3.82% |
| bridge-30 | 129.12 ms | 135.11 ms | 412,752 | 395,152 | -4.26% |
| articulation-30 | 52.28 ms | 65.87 ms | 67,695 | 67,619 | -0.11% |
| random-2000 | 78.24 ms | 48.88 ms | 534,905,920 | 534,273,598 | -0.12% |
| arrow-2000 | 21.14 ms | 38.92 ms | 31,966 | 31,966 | 0.00% |
| shell-2000 | 53.40 ms | 47.26 ms | 42,565 | 42,565 | 0.00% |

Five-sample threshold extension:

| Shape | Old median | Boundary median | Old flops | Boundary flops | Flop delta |
|---|---:|---:|---:|---:|---:|
| bridge-40 | 120.89 ms | 125.31 ms | 1,096,243 | 1,039,386 | -5.19% |
| grid-55 | 122.80 ms | 116.28 ms | 1,472,636 | 1,425,073 | -3.23% |
| articulation-48 | 51.74 ms | 62.30 ms | 108,321 | 108,245 | -0.07% |
| random-3000 | 95.93 ms | 69.05 ms | 1,808,553,115 | 1,808,213,065 | -0.02% |
| band-5000 | 39.57 ms | 51.62 ms | 244,797 | 244,797 | 0.00% |
| arrow-5000 | 25.39 ms | 40.79 ms | 79,966 | 79,966 | 0.00% |
| shell-5000 | 68.66 ms | 62.19 ms | 89,249 | 89,249 | 0.00% |

Emitting each local COO edge once did not change any structural result.  It
reduced boundary-worker allocation bytes by 3-12%; random-2000 median time
fell 4.36%, while the other timings ranged from -0.9% to +2.7% noise.

## Profile-guided RGSUB follow-ons

A 3-second, 10 ms `sample` capture mapped the hot hashed frames through the
native side map.  Of 252 main-thread ticks, 245 (97.2%) were waiting in
`flush_blocks -> pthread_join`; the four workers averaged 3.76 active cores,
so this was useful parallel work rather than lock contention.  The old
four-job waves nevertheless created more than 105 sampled workers per second,
with roughly 30 ms observed lifetimes.  The native merge/and-not helpers were
only 5.5-7.6% of worker leaves and already compiled to unrolled AArch64 NEON
`ldp`/`bic`/`cnt`/`udot` loops.

The retained scheduler therefore shares each phase's immutable job array,
launches a CPU- and memory-capped worker set once, writes proposals into fixed
indexed slots, and performs deterministic exact acceptance afterward.  On the
18-core measurement host, eight workers already improved grid/blocks/bridge
by 22-26%; allowing all 18 cores for small jobs improved blocks another 4.38%
over 16 workers.  The 128 MiB scratch guard reduces concurrency automatically
for the largest terminal-expanded blocks.  Against four-job waves, an
eight-worker lower bound for the final CPU-scaled policy produced the following
seven-run medians:

| Per-block budget | grid-40 | blocks-22 | bridge-30 | random-2000 |
|---:|---:|---:|---:|---:|
| 2.5M | -24.17% | -25.00% | -26.08% | -0.24% |
| 5M | -26.81% | -27.44% | -26.78% | -0.27% |
| 10M | -28.24% | -27.60% | -27.97% | -0.49% |
| 20M | -29.96% | -29.46% | -28.58% | -0.63% |

The raw-return bitset ABI was measured independently with an equal 65,536
words per sweep.  It was 4.59x faster at 4 words/row, 4.13x at 16, 3.96x at
32, 3.27x at 64, and 2.54x at 128.  The output count and mutated destination
matched the boxed entry exactly.  Across full RGSUB runs the change improved
all nine tested shapes by 0.55-2.24%.

Two further duplicate symbolic passes were removed.  Each block's identity
seed now reuses counts already computed by `SparseAnalysis.new`, and the
initial postordered score uses its retained count array.  The largest full-run
effect was random-2000 at about -14%; structured cases were mostly below the
timing noise floor.  Finally, the remaining fresh postorder analysis was
replaced by the exact etree relabel transform.  With search work set to zero,
setup fell 8.26-10.11% on grid/blocks/bridge/random-2000, 15.17% on
random-5000, and 1.74% on shell-5000.  Forty-four shape/stream comparisons and
dedicated disconnected, duplicate-edge, upper-triangle, and lower-triangle
oracles matched fresh symbolic analysis exactly.

Exact acceptance no longer requires an n-element candidate copy per block.
Once all proposal workers are joined, the order is coordinator-owned: it is
spliced in place from one reusable typed undo segment, globally rescored, and
restored on rejection.  Seven-run medians improved grid-55 1.97%, blocks-22
3.61%, and random-2000 0.48% (the other five shapes were within +/-0.5%).
Allocation bytes fell 314,336 on grid-55, 516,240 on blocks-22, and 155,784 on
random-2000; 44 case/stream pairs retained identical fill, flops, and checksum.

The last dynamically grown proposal-local container was an identity block seed
whose final length and element range are known before construction.  Replacing
it with a directly indexed `u32` buffer removed 61 allocations and 81,416 bytes
on grid-55, 64 allocations and 47,936 bytes on blocks-22, and 11 allocations
and 16,808 bytes on shell-2000.  Seven-run medians improved grid-40 2.31%,
grid-55 3.57%, and blocks-22 3.09%.  Fifteen-run extensions on articulation,
arrow, and shell were neutral (all within +0.11%), and 44 case/stream pairs
again retained identical structural results.

The macro RGSUB round remains useful when quality is the objective: at 20M
words it improved 17 of 57 direct cases.  In the default portfolio, however,
the downstream exact-gated lanes erased its gains on all six tested shapes.
The one-round default kept the same final permutations while improving
grid-70 2.71%, bridge-40 3.16%, and articulation-30 0.79%; the other three
medians were within 0.5%.  There is no safe size-only or "round zero made no
change" cutoff, so direct `rgsub_boundary` retains both rounds.

## Watcher MINL

Watcher MINL maintains stable fill-edge endpoints, exact four-vertex witness
supports, and a fixed wake queue.  It fails closed above its size/fill caps.
The candidate is computed from the preserved pre-scan seed and merged only
after the historical nonlinear descents; this late exact gate is important,
because merging it earlier changed the later basin and regressed grid-45.

Five fresh-process alternating end-to-end samples:

| Shape | `best` median | `best_watch` median | Flop delta | Time delta |
|---|---:|---:|---:|---:|
| grid-45 | 1640.10 ms | 1656.13 ms | 0.000% | +0.98% |
| bridge-30 | 1272.41 ms | 1284.13 ms | -0.100% | +0.92% |
| random-750 | 3497.27 ms | 3487.23 ms | -0.0059% | -0.29% |

The lane remains opt-in: it is exact-monotone after the late merge, but this
corpus does not support paying its extra completion construction by default.

The reused symbolic-score workspace is serialized per analysis so public
read-like scoring remains correct when an analysis is shared across threads;
worker-private analyses never contend.  Nine-run RGSUB comparisons against the
unlocked build were grid-40 +0.69%, blocks-22 +0.43%, bridge-30 -0.41%, and
random-2000 -0.19%, all with identical structural results.  An eight-thread,
40-iteration regression interleaves owned counts, fill/flop, flop-only, and
prefix queries over two permutations.

Zero-length prefix reads now validate missing paths and directories rather
than succeeding without opening the path.  In a 20,000-call sweep that edge
case rose from 1.51 to 11.66 us; the real 16- and 128-byte probe paths were
unchanged within 0.5% (11.65 -> 11.69 us and 11.72 -> 11.78 us).

## Rejected or non-default mechanisms

| Mechanism | Evidence | Disposition |
|---|---|---|
| RCM / Sloan reorderings | grid-20 was about +97% flops; disconnected grids about +39%; both slower | Explicit APIs only; never enter best-ordering automatically |
| Structural top-four pool | No exact final quality wins; added allocations and scoring | Default off |
| Dense-threshold diversity | No exact final quality wins on the synthetic corpus | Default off |
| In-core native and-not bitset call | Standalone native assembly vectorized (`bic`, `cnt`, `udot`), but replacing the typed in-core loop regressed 2-4% | Reverted; keep the native helper only where call overhead amortizes |
| Broad threaded relabeling | About +10% wall time on the matched workload | Do not promote without a lower-overhead fixed worker executor |
| Synchronous singleton RGSUB tails | Seven-run medians regressed blocks-22 2.73%, bridge-30 1.61%, and grid-55 1.10%; other shapes were neutral/noisy | Reverted; even a one-job native worker is not the measured bottleneck |
| `fstat`-capped prefix allocation | A 100 MB request against `README.md` took 14.60 -> 19.93 us (+36.6%); lazy `malloc` kept both at about 3 MB RSS | Reverted; normal SciIO probes already request only 4-128 bytes |

All reported candidates preserve exact fill/flop recomputation and permutation
checks.  Candidate-local scores are never treated as authoritative acceptance.

## Large sparse policy cleanup

The follow-up campaign evaluated all 45 public rows with more than 10,000
vertices at stream 7 and a 150,000,000 word-operation budget. The first
exploratory policy improved 17 rows, tied 28, and reduced geometric-mean exact
flops by 1.3747%, but it was not retained: it contained a public-corpus-derived
AMF metric (`SqLooseDivHalfWF`), absolute 700k-1.2M entry and 8k-20k core
bands, an `n > 10k` admission gate, and a fixed `+257` search-stream offset.
Those choices were removed rather than rationalized after the fact. This
forfeited the exploratory policy's 25.48% in-sample flop win on
`pooling_sppc3pq`.

The final automatic policy is admitted only by algorithmic resource and work
models:

- sparse core lifting eliminates exact degree-three vertices and bounds the
  reducer, retained core, and one-shot AMD pool inside a 128 MiB envelope;
- iterative flat-CSR biconnected decomposition similarly gives each local AMD
  a precomputed, fail-closed pool;
- the terminal-RGSUB coordinator and the aggregate worker set have separate
  128 MiB estimates, including boxed sorting state, edge copies, and three
  dense worker bitmaps;
- secondary search streams are relative XOR splits of the caller's stream, so
  each is a bijection rather than a selected absolute seed; and
- all candidates are complete permutations and are accepted only after exact
  whole-pattern rescoring.

The generalized result was 34 wins, 11 ties, and zero regressions versus the
historical baseline. Its geometric-mean exact-flop reduction was 1.2459%.
The largest exact changes were:

| Row | Baseline flops | Generalized flops | Delta |
|---|---:|---:|---:|
| crudeoil_pooling_dt3 | 44,330,840 | 37,580,702 | -15.2267% |
| cont6-qq | 802,438,606 | 736,167,350 | -8.2587% |
| methanol400 | 2,047,001 | 1,884,991 | -7.9145% |
| crudeoil_lee4_06 | 39,680,611 | 38,146,369 | -3.8665% |
| gabriel10 | 1,385,204,968 | 1,337,109,769 | -3.4721% |
| glider400 | 345,070 | 334,627 | -3.0263% |
| pooling_sppc1pq | 156,089,848 | 153,393,644 | -1.7273% |
| mpbp_35 | 1,504,061 | 1,481,326 | -1.5116% |

The corpus is public and influenced the implementation campaign, so the table
is not presented as held-out generalization. Counterchecks used generated
families and independent graph seeds: 30 cases straddling 10k vertices yielded
4 wins, 26 ties, and no regressions; five random seeds yielded 4 wins and 1
tie; and shell cases at 23,167/23,168/23,169 vertices all tied, with no quality
cliff at the dense-bitmap boundary. Across seven streams, the former absolute
257 choice was best for one generated grid but not for a generated bridge.

Reproduce the public-corpus sweep with
`bench_ssi_corpus_ordering.rb --gt-10k --stream 7 --budget 150000000` after
compiling `ssi_corpus_ordering.w`. The runner checks the row dimensions,
permutation, exact fill/flops, checksum, and repeat determinism. Wall-clock
numbers from the parallel census are intentionally omitted; only matched
fresh-process runs should be used for timing claims.
