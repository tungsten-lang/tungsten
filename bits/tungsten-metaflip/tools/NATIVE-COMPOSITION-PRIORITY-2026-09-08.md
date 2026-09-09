# Native composition: fair priority scheduling — 2026-09-08

Follow-up to `0fc7038c`. Ordinary MetaFlip now orders its pending native
composition work by an advisory rank ratio, while retaining age-based service
and exact verification. This changes when useful constructions are verified;
it does not claim a new rank record or a general throughput improvement.

## Scheduling and recovery

The scheduler examines at most 128 tickets starting at the oldest unfinished
ticket. Three of every four completions choose the smallest predicted-rank /
baseline ratio; ties prefer smaller rank, then earlier ticket. The baseline
is naive rank, reduced by an advisory archived bound when available. The first
completion and every fourth thereafter serve the oldest pending ticket.
`METAFLIP_COMPOSITION_FIFO=1` restores FIFO for matched controls. No price
prunes a recipe, and malformed prices cannot bypass the full tensor gate.

Out-of-order results use `MFC_RESULT2`, which records the original task ticket
alongside its task hash, output hash, ordered shape and rank. Results remain
append-only in completion order. A checksummed `MFCS1` record stores the
completion count, first unfinished ticket and four 32-bit completion masks.
Its invariant is `count = first - 1 + popcount(masks)`. State size is constant;
it is not proportional to queue length.

Commit order is exact result, scheduler state, then visible completion count.
On restart, an already-written result is fully reconstructed and checked
before either missing state or a lagging visible cursor is advanced. Legacy
FIFO result prefixes remain byte-for-byte unchanged. A missing scheduler
record with a nonzero v2 cursor, corrupt checksum, conflicting result or
invalid window fails visibly rather than acknowledging unverified work.
Schedule/cursor write failures also report an explicit composition error.

The current single native background worker, source-job batching, and stop
checks are unchanged. Fairness assumes the selected recipe completes: an
invalid or over-budget selected recipe still pauses composition visibly.
The 128-ticket window bounds scheduling work, not retained disk bytes or the
entire backlog.

## Matched frozen-queue experiment

Both arms start from the same native refinement of the external 4x8x4/r94
parent, with 105 identical recipes and two shared initial completions. Each
arm finishes all 105; independent full coefficient expansion verifies all
210 outputs and confirms identical final output sets. No work is discarded.

| Exact construction | FIFO completion | Priority completion |
| --- | ---: | ---: |
| 7x12x12, rank 651 | 47 | 7 |
| 7x16x16, rank 1132 | 48 | 4 |

Shapes above are dimension-sorted; archived tensors retain their ordered
dimensions. These reproduce known local constructions. This one golden
workload demonstrates earlier useful completions, not a universal search
advantage or a wall-clock speedup. The fixture remains an external campaign
artifact, not a newly imported distributable seed.

## Focused verification

- Native mask tests complete 1,024 tickets out of order across eight windows,
  including 32/64/128-bit boundaries, duplicate/out-of-window rejection and
  oversized masks.
- An independent 144-ticket queue replay verifies every tensor and checks
  the oldest-ticket service rule, window bound and ticket uniqueness.
- Queue tests cover result-before-state recovery, lost cursors, corrupt or
  missing v2 state, paged/legacy migration, selective leaf repricing, stop,
  deduplication and forged prices. The external 105-recipe chain passes.
- The matched priority test independently replays all 210 completions and
  asserts that both target constructions arrive earlier with priority.
- Public fleet checks cover narrow feedback, rectangular restart, disabled
  refinement, asynchronous interrupt and raw-TUI reset. Final current-binary
  canary details are below.
- All 317 runtime file digests and 168 source-manifest entries are checked;
  generated GPU sidecars are excluded.

From the repository root, build the focused driver and run the tests:

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/packed_composition_test.w \
  --out /tmp/metaflip-composition-test --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/composition_queue_test.py \
  /tmp/metaflip-composition-test /path/to/4x8x4-r94.txt
python3 -B bits/tungsten-metaflip/spec/composition_priority_test.py \
  /tmp/metaflip-composition-test /path/to/4x8x4-r94.txt
```

The queue test also runs without the optional external parent. The matched
priority experiment requires that exact parent (raw SHA-256
`2302b77841e213a9c03c32fc0e9e2dcdf947177501199963f65f62a3b231e047`).

## Short public canary

The rebuilt release/native binary has SHA-256
`2671528dfe59e56fdebf6c82bfab4f3054b6d15a90aa851c308598c96913a69a`.
A 15-second, low-priority CPU-only 5x5 run used one worker and 65,536-step
epochs. It reported 1,113,915,392 moves, completed all 18 source jobs and
88/3,951 composition jobs, and used eight feedback seeds. All 442 narrow
objects and all 88 completed compositions were independently verified.
There were zero composition failures and no owned child survived shutdown.

The temporary spool held 1,645 files / 7,164,118 logical bytes. At roughly
0.4-second sampling intervals, 35 live samples observed peaks of 29,776 KiB
for the main process and 48,752 KiB for all owned processes. This is a short
resource canary, not a matched performance comparison or evidence of a
long-running memory plateau. The remaining 3,863 composition jobs were
pending, not verified. The temporary spool was removed after the audit.

## Bounded parent search: no new bound

The useful rank-85 4x7x4 parent has 38 disjoint shared-factor pairs, giving
scale-three cost 651. A 39th pair at that rank would lower the price to 648,
so two bounded native walks targeted pair-composition cost rather than rank
alone. Both used rank debt 2, density slack 8 and one low-priority CPU:

| Run | Trials | Chunks/trial | Moves/chunk | Observation interval | Seed | Attempts |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Coarse | 32 | 64 | 65,536 | 4,096 | 67,041 | 134,217,728 |
| Fine | 32 | 16 | 4,096 | 64 | 71,291 | 2,097,152 |

Across 136,314,880 distinct attempts, 41,988,039 flips were accepted. Neither
run improved cost 651, rank 85 or retained density 764. The 64 distinct
endpoints then underwent native pair/matrix cleanup, bounded basis changes
and coordinate projections. All 2,210 resulting narrow objects checked
exactly; projected minima 3x4x7/r68 and 4x4x6/r75 were worse than the packaged
r64 and r73 witnesses. This is a bounded negative, not an impossibility claim.

These trials exposed an offline scout bug: it reported successful saves
without ensuring the output directory existed or checking the write. The
scout now creates the directory, checks the write and reads back identical
bytes before reporting success. Focused tests cover missing directories,
blocking files and failed tensor writes, plus existing exact/repeatability
and above-rank-64 checks (four tests, 185 assertions). The same seeds were
replayed after the fix to retain independently checked endpoints; repeats
are not counted as new independent search attempts. No unbounded search was
left running.

Open integration work includes a disk-budget policy, global changed-leaf
propagation, recursive wide composition and cross-shape fleet dispatch.
