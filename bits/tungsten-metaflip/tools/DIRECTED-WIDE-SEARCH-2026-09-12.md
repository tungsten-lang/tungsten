# Bounded directed wide-search experiment — 2026-09-12

Historical measurement: this screen used the former per-move density cutoff.
The later archive-only density change removes that cutoff on all packed
workers and limits history aspiration to new rank bests. Its split/history
rules remain. The measurements below must not be attributed to that new
policy without rerunning the sweep. Current status marks it explicitly as
`walk_density=unrestricted`.

Decision: retain an opt-in experimental CPU island; keep the baseline default.
This is not a record-finding improvement claim or an exhaustive state search.
It applies to the packed 8x8 through 16x16 squares, not the narrow/GPU backend.

## Policies and implementation

`METAFLIP_WIDE_DIRECTED=partners|nonbacktracking|tabu` selects one experimental
island (the last CPU worker). `0` or unset keeps every island on the baseline.
With `-J 1`, the single worker is experimental. CPU islands remain private;
no shared visited table or contention is introduced.

- `partners`: choose a bucket known to contain an exact equal-factor pair,
  then a member and an equal-factor partner. Hash collisions alone cannot
  make a bucket eligible. Refresh only buckets touched by a transaction.
- `nonbacktracking`: additionally reject the previous state and no-op state.
- `tabu`: additionally reject a hit in a 65,536-slot direct-mapped history.
- All three preserve the rank/density acceptance gate and strict-new-best
  aspiration, and add splits on no eligible edge or 256 consecutive rejects.
  After that rejection threshold the bounded history is forgotten. Splits
  reset the immediate-inverse guard. These escape changes mean `partners`
  versus baseline is not a pure one-lever partner-selection ablation.

Fingerprinting XORs two salted 63-bit hashes of each full term, independently
of term order. This is a heuristic 126-bit fingerprint, not exact identity or
equivalence-class canonicalization. Hash collisions can reject valid moves;
eviction, aspiration, and forgetting allow revisits. `directed_novel_hashes`
counts misses in the current cache, NOT globally distinct states. The index
samples eligible buckets, not legal graph edges uniformly.

The history alone costs about 1.5 MiB, plus the per-axis eligibility index,
on the single experimental worker. Baseline workers retain `ffws_work`.
The coordinator adapts the experimental attempt budget to baseline epoch
time (target capped at 50 ms); matching attempt counts would unnecessarily
hold the cohort behind more expensive proposals. Counters are published only
after worker joins, never read concurrently from mutable worker state.

## Counterbalanced screen

64 runs: squares 8, 12, 15, 16; RNG seeds 19071 and 19072; four policies; two
orders (baseline/partners/nonbacktracking/tabu, then the reverse). Each run
received one second of wall time in 4,096-attempt chunks, with a full-state
snapshot approximately every 100 ms. Initialization was outside this window;
snapshot serialization was inside it. Raw process wall time was also retained.
Build: release/native/no-LTO. The user's live search continued on the same
host, so these short, non-exclusive-host measurements are screening evidence,
not a stable hardware throughput qualification or a fleet-wide speedup.

Mean accepted pair flips/second (accepted is not unique):

| Square | Baseline | Partners | Nonbacktracking | Tabu |
|---|---:|---:|---:|---:|
| 8 | 1,931,120 | 2,171,062 | 1,976,381 | 1,859,325 |
| 12 | 1,619,844 | 1,512,382 | 1,433,223 | 1,441,792 |
| 15 | 1,466,871 | 853,823 | 853,042 | 842,853 |
| 16 | 201,110 | 931,299 | 950,846 | 57,614 |

Exact unique snapshots / snapshots, summed within each run (not globally
deduplicated across runs):

| Square | Baseline | Partners | Nonbacktracking | Tabu |
|---|---:|---:|---:|---:|
| 8 | 40/40 | 38/38 | 37/38 | 39/39 |
| 12 | 40/40 | 36/36 | 36/36 | 36/36 |
| 15 | 40/40 | 36/36 | 36/36 | 36/36 |
| 16 | 40/40 | 27/36 | 30/36 | 33/36 |

All 599 snapshots and 64 best endpoints passed independent Python expansion
of the full GF(2) matrix-multiplication tensor. Snapshot uniqueness compares
complete sorted coefficient bytes, not the heuristic state fingerprints.
Baseline does not compute per-move history counters; its hash-cache counters
are not comparable to the directed counters.

No run lowered rank. At 15x15 the public rank-2058 start reached density
64,364 or 64,355 in directed modes versus 64,365 for baseline. This is a small
same-rank change, not an improvement on the user's stronger rank-2008 seed.
At 16x16 legal-partner/nonbacktracking acceptance was much higher, but exact
sample repeats were also more frequent. Strict tabu had thousands of history
resets per second and substantially lower accepted throughput. None of this
establishes increased probability of a new rank record. Longer runs should
measure rank/density outcomes and sampled novelty, not just attempts/second.

## Reproduction and evidence

From the repository root:

```sh
bin/tungsten compile bits/tungsten-metaflip/spec/wide_directed_bench.w \
  --out /tmp/metaflip-directed-bench --release --native --no-lto
python3 bits/tungsten-metaflip/tools/bench_wide_directed.py \
  /tmp/metaflip-directed-bench /tmp/metaflip-directed-new-run
```

The driver uses bundled/composed starts, never the user's checkpoint. Raw
stdout/stderr, failures/timeouts, timing and independent verification results
are recorded before any assertion stops the sweep. Output must be a new
directory. The original artifacts are outside the repository at
`/tmp/metaflip-directed-ablation-20260912/`; hundreds of tensor snapshots are
not added to Git. Fingerprints of the original evidence:

```
results.jsonl b48e5db2ed391f27c5840f4897a0f0615a8638bb00168d4bb9eddf3a46552c74
summary.json  a163f3da30b1dd2edcb2d403f680f06cfd95d4ba7f86845dbaa594bae63e5762
benchmark binary 777f932a5d913680266f9c6a7c897d1d5048704f40ae548ecebf8e9b7f665b9d
```

The measured binary predates extraction of the identical rejection predicate
into `ffwd_guard` for focused aspiration/inverse tests. No new performance
claim is made for that refactoring.

Focused checks cover all 27 square/policy combinations, incremental hashes
against full recomputation, exact eligible-index membership and witnesses,
rollback, term-order invariance, aspiration, invalid configurations,
counter accounting, exact current/best tensors, single-/16-worker deadlines,
public CLI opt-in/default routing, and actual styled TUI resize/quit behavior.

## User's rank-2008 checkpoint

Independent exact verification found rank 2008, density 49,384 and SHA256
`4f9329cb130a17dd43d708a4191e96a458f5fc935ccdc930864ef06d4db423e6`.
The restored historical rank-2008 seed had density 50,584 and canonical
SHA256 `e6ac606e71a90654732f637054ea79eea8d1bfdd53e572d2d476cc87770afc48`.
Thus the live run found a different representation with 1,200 fewer bits
(about 2.37%), not a previously unavailable rank. The running process and
checkpoint were left untouched. Its provenance is described in
[the seed audit](LARGE-SQUARE-SEEDS-2026-09-12.md).
