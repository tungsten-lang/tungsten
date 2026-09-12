# tungsten-metaflip

`tungsten-metaflip` is the distributable core of Metaflip: a domain-neutral
exact-gated search coordinator plus an adaptive production fleet for low-rank
matrix-multiplication tensor decompositions over GF(2). The tensor fleet keeps
independent CPU basins and schedules a diverse portfolio of Metal kernels,
with the GPU enabled by default when supported.

The production tensor fleet remains intentionally GF(2)-only. The
package also includes a domain-neutral in-process search coordinator, the
pure-Tungsten GPU sources the tensor fleet builds, the small set of exact
schemes needed to start supported campaigns, and reusable proof primitives.
Long-running proof campaign manifests, ternary search, experiment journals,
and the full certificate collection remain outside this bit. The focused
Proximity benchmarks retained under `spec/` exercise the public adapters but
do not ship proof generators or submission artifacts.

```text
tungsten-metaflip/
├── Bitfile
├── bin/
│   ├── metaflip
│   └── metaflip.w
├── cloud/cuda/
│   ├── build_777.sh
│   ├── metaflip_cuda_777.cpp
│   └── test_777_host.sh
├── lib/metaflip.w
├── lib/metaflip/
│   ├── scheme.w
│   ├── verify.w
│   ├── compose.w
│   ├── proof.w
│   ├── proof/
│   ├── search.w
│   ├── search/
│   ├── fleet.w
│   ├── rect.w
│   ├── tui.w
│   ├── paths.w
│   ├── fleet/
│   ├── rect/
│   ├── strategies/
│   ├── kernels/
│   └── seeds/
└── spec/
```

## Build

A Tungsten compiler is required both to build the coordinator and, for the
current release, at run time when the fleet materializes specialized workers.
Worker builds resolve the driver through `METAFLIP_TUNGSTEN`, `TUNGSTEN_BIN`,
`TUNGSTEN`, `TUNGSTEN_ROOT`, and finally `tungsten` on `PATH`.
From the Tungsten monorepo:

```sh
cd bits/tungsten-metaflip
tungsten build
bin/metaflip
```

`tungsten build` reads the `Bitfile` executable declaration and builds
`bin/metaflip` from `bin/metaflip.w`. Run it again after source or compiler
changes. From a standalone package checkout, use the same last two commands.
The fleet finds its packaged runtime automatically.

The executable's Bitfile defaults to `profile: "release", native: true`, so
the ordinary build optimizes the hot loop and targets the host CPU. Use
`tungsten build --debug` to override optimization for debugging, or an explicit
`--cpu` for another CPU of the same architecture. Application cross-compilation
uses `bit build --target TRIPLE`; the root build's `--target` option instead
controls compiler release artifacts. Other bits keep their
own build defaults. Executable declarations also accept `opt_level: "2"`
and a quoted, whitespace-separated `cflags: "-fno-omit-frame-pointer"` string.
These are compiler tokens, not shell commands; changed flags invalidate the
build cache. Do not add `--fast` by default: it separately relaxes floating-point
semantics.

Defaults are `-J max(logical CPUs - 2, 1)`, GPU enabled, TUI enabled, and
`--secs 0` (no time limit). On an 18-core host this starts 16 CPU islands.
Override them with `-J N`, `--no-gpu`, `--no-tui`, or `--secs N`.
With no campaign selector, MetaFlip cycles through **all 43 supported live
profiles**: squares 2x2 through 16x16, then the 28 supported rectangular
profiles. Unresolved shapes get **60 seconds of rank search**, using the
configured CPU allocation and GPU where supported. Proved-optimal shapes instead get
**composition-parent visits**: initially 15 seconds, falling to 7 then 3 after
completed visits without a downstream gain, or rising to 30 after a verified
downstream rank decrease. Pending refinement work is not counted as failure.
The time is always capped by `--cycle-secs`; `--cycle-policy uniform` restores
equal time slices. No supported shape is removed or permanently starved.
Exact shutdown/checkpointing finishes before the next
shape starts, so visits can take slightly longer than a minute, especially
on a cold GPU cache. The foreground process replaces its search arena between
visits; it does not accumulate workers or memory from completed campaigns.
Checkpoints and banks remain separate for each shape and are reloaded on
later visits. `n` ends the current visit early (exact shutdown and
checkpoint) and moves to the next shape; `q` or Ctrl-C stops the entire
cycle, not just the current shape.

Use `--tensor 5x5` to stay on one shape, or `--tensor all` to explicitly cycle.
`--cycle-secs N` changes the per-shape ceiling; `--cycle-shapes
5x5,4x5x7,7x7` selects an ordered subset. `--secs N` sets one overall deadline,
not reset between visits; initialization and in-flight work may finish after
it. `--rounds N` remains a per-visit worker-round cap; the finite 2x2 parent
enumerator is bounded by its 216 codes and visit time instead.
`--rect` still selects the separate adaptive rectangle-only portfolio and
is **not needed** to include rectangles in the default cycle. Single-shape
seed/record/checkpoint/near-bank/GPU-binary/Core-ML overrides require an explicit
`--tensor SHAPE`, preventing accidental reuse across incompatible shapes.
Specialized GPU workers are built and cached on first use. Press `q` or
Ctrl-C in the TUI to stop.

Squares **8x8 through 16x16 are CPU-only**: they use private CPU islands
with packed multiword factor storage, beyond the narrow/Metal engine's
current 7x7 limit. `-J` has the same default and override; a requested GPU
is explicitly reported as unavailable (`gpu_supported=0`). The TUI keeps
the same dashboard layout, colors, rank/density sparklines, CPU-island rows,
effectiveness section and rank timeline. Per-island rates/ranks are snapshots
from completed worker epochs; their age is shown. Unsupported GPU, diversity
and refinement features are labeled unavailable, not populated with proxy data.
For example:

```sh
bin/metaflip --tensor 16x16
bin/metaflip --cycle-shapes 8x8,12x12,16x16 --cycle-secs 60
```

These workers start from pinned published GF(2) decompositions or better
full-tensor-verified Kronecker products/projections of bundled smaller seeds
(or `--naive`), perform multiword pair flips and
bounded splits, and exactly verify every promoted checkpoint. Large-square
`--seed` and `best.txt` use canonical **MFW1** hexadecimal masks, not the
narrow decimal-mask format. A malformed checkpoint is rejected without
overwriting it, and `--naive` never replaces a better saved result. The new
backend does not yet run GPU, Core ML, or the small-shape refinement/portfolio
strategies. Composed starting ranks are not claims of new records.

The 2026-09-12 large-square refresh adds 12 literal-distinct published
certificates (1,316,280 bytes total), with exact upstream hashes and MIT
attribution in `lib/metaflip/manifests/wide-seeds.tsv`. A normal launch needs
no download and no Python. Default GF(2) reference ranks for 8..16 are
**329, 486, 651, 873, 1068, 1426, 1725, 2058, 2209**. The TUI says
"reference", not "proved optimal"; characteristic-zero-only and commutative
catalog results are not GF(2) tensor records.

At startup, workers are distributed across at most four full-term-distinct verified starts:
published seeds and alternative small-seed compositions within 5% of the
leader. One published near-best seed was available for 9, 11 and 13; the other
sizes have 2–4 automatic starts. `--seed` or `--naive` pins a single start.
Higher-rank published alternatives remain bundled for explicit `--seed` use.
Packed squares also have an **opt-in directed-search arm**:

```sh
METAFLIP_WIDE_DIRECTED=tabu bin/metaflip --tensor 16x16
```

Only the last CPU island changes; the others retain the baseline walker.
`partners` selects actual equal-factor pairs, `nonbacktracking` additionally
blocks immediate returns, and `tabu` additionally checks a 65,536-slot recent
fingerprint table. `0` (the default) disables the experiment. With `-J 1`, the
one worker runs the selected policy. Nothing changes for narrow/GPU workers.
The experimental island's chunk size adapts to baseline worker time so it
does not hold the cohort to an equal count of more expensive legal proposals.
Status reports `directed_*` counters from joined epochs, and the TUI footer
identifies the policy and island. Fingerprints are two 63-bit hashes, not
an exact no-revisit certificate: collisions, eviction, aspiration for a new
best, and bounded forgetting all affect the heuristic. Sampling is uniform
over eligible hash buckets, not uniform over all legal graph edges. Exact
tensor validation still gates every promoted checkpoint.
`directed_novel_hashes` counts cache misses, **not** globally distinct states;
evicted or forgotten states can be counted again. The bounded
[64-run experiment](tools/DIRECTED-WIDE-SEARCH-2026-09-12.md) found mixed results
and no lower ranks, so no directed policy is enabled by default.

See the [source and field audit](tools/LARGE-SQUARE-SEEDS-2026-09-12.md).
Existing historical 13x13 rank-1402 and 15x15 rank-2008 witnesses can be
restored from local Git history with `tools/recover_wide_local_seeds.py
--repo /path/to/tungsten`. This writes only new local checkpoints, never
overwrites existing state, and does not bundle coefficients with unresolved
redistribution provenance. Those stronger local starts take precedence.

Offline refresh/replay (raw source JSON stays outside the repository):

```sh
python3 tools/import_wide_seeds.py --runtime lib/metaflip
python3 spec/wide_seed_import_test.py
```

For the solved 2x2 parent, a cycle visit enumerates all 216 GL(2,2)^3 basis
codes (36 full-identity-distinct rank-seven tensors) into the durable exact
refinement queue. Later visits reuse its cached tickets while processing
composition work: no CPU/GPU rank-six search or GPU compilation is started.
Explicit `--tensor 2x2` and `--naive` retain ordinary walker behavior.
Other optimal profiles retain diversity/density walking and same-rank intake;
their rank-drop-only surgery lanes are disabled. Proof metadata is explicit
in `seeds/bounds.w`: the GF(2) Hopcroft--Kerr thin family and the repository's
checked n324 quotient-rank proof, never a failure-to-improve heuristic.

`search_purpose`, `proven_rank`, `cycle_seconds`, `parent_misses`, and
`downstream_saved` expose the policy in status. Utility counts strict rank
decreases against a previously verified downstream target in this campaign's
archive; first observations and rank ties earn no credit. Axis permutations
share one target. This is not a world-record counter or a causal proof that
one parent alone produced the improvement, and it never replaces exact
tensor verification. Same-rank parents remain eligible regardless of credit.
An explicit shared `--status` path keeps its shared intake queue, but uses
fixed 15-second parent slices (capped by `--cycle-secs`) under the adaptive
policy: mixed-shape gains cannot safely be attributed to a single parent.

Candidate admission now includes deterministic exact algebraic cleanup:
terms sharing two factors are merged by XORing the third, sweeping axes
`0,1,2` until no further pair reduction is possible. A native GF(2) matrix
pass then factors each group sharing just one factor, replacing it when its
matrix rank is smaller and repeating to a fixed point. This catches reductions
that pair cleanup cannot see. The coordinator applies both passes
before objective/archive comparisons to CPU endpoints, GPU results
(including late results), and rectangular/composed candidates. A raw-rank
nonleader can therefore become a leader after cleanup. The wide-host intake
window can defer inspection, but does not reject a candidate by its raw rank.
Freshly installed CPU seeds remain pending for their first inspection.

The cleanup uses reusable scratch space and exact-checks the result before
updating the saved best. Current worker terms, hash chains, RNG and move count
are preserved; the density delta is rebased. It does not run in the per-flip
loop or silently rewrite the declared-rank contract of scheme-file loaders.
The default is one deterministic axis order, not an optimal-rank oracle or
all six orders. There is no Ruby/Python runtime dependency.

Focused native tests cover square/rectangular admission, cascading reductions,
rejection without payload mutation, source-mask validation and continued
walking. `spec/pair_cleanup_parity_test.py NATIVE_TEST_BINARY` compares 480
native cases against the offline pair reducer over all six orders.
`spec/matrix_cleanup_parity_test.py NATIVE_TEST_BINARY` compares 700 matrix
compression/neutral-basis cases with an independent row-equation oracle,
including 63-bit masks. The bounded `spec/pair_cleanup_bench.w` measured
matrix cleanup alone at 0.6–3.1 microseconds and combined admission at
5.2–131.6 microseconds on the local 2x5x6/r47, 5x5/r93 and 7x7/r247 controls
(64 repetitions). These are local cold-path timings, not a fleet throughput claim.

Square and rectangular fleets now enqueue distinct exact-gated candidates
automatically, including rank ties and nonleaders. Identity includes the
ordered shape and the complete sorted term multiset. SHA-256 locates an
immutable object; full bytes and the tensor identity are checked separately.
The immediate cleanup remains synchronous, but the cold refinement runs in
one low-priority (`nice -n 10`) native child with at most two jobs per batch:

- matrix compression and six bounded one-axis basis proposals;
- every single-coordinate projection of the cleaned source and its best
  grouping endpoint, followed by exact pair/matrix compression;
- full tensor verification of every output, including unchanged-rank bases.

The queue is on disk beside the status file, in `status.txt.refinement/`.
`objects/` holds canonical `MFR1` tensors; `tasks/` and `results/` bind input
and output identities; `by-shape/` indexes projected outputs. Active worker
memory is bounded and overflow remains as deferred disk tickets. This is not
a fixed disk-byte quota: long runs can accumulate artifacts. Disk/write or
validation failures increment `refine_failures`, not successful-job counts.
Completed manifests and the consumed cursor support restart with the same
status path/run tag. `--naive` and the space-key reset use fresh spool
generations, so earlier refinement does not leak into a fresh frontier.

Same-shape proposals enter the ordinary exact seed/archive path; useful rank
ties are not discarded by a rank-only intake filter. Seed delivery is bounded
and does not stop result collection. Different shapes remain in the indexed
artifact archive. The TUI and status expose submitted/completed/pending jobs,
outputs, cross-shape outputs, failures and seed-use counts. Submitted/completed
persist across restart; output/duplicate/seed-use counts are per process.
Graceful shutdown stops the child but preserves unfinished tickets. Use
`METAFLIP_REFINEMENT=0 bin/metaflip ...` for an unchanged-search control.

`spec/refinement_worker_parity_test.py NATIVE_TEST_BINARY [EXTERNAL_4x8x4]`
independently replays the complete bounded worker family, canonical objects,
rank-tie intake, restart, cancellation and corrupted-input rejection.
The optional external r94 parent reproduces 4x7x4/r85 without redistributing
that imported input. `spec/refinement_fleet_test.py bin/metaflip` exercises
both public coordinators, same-shape feedback and stopped-child checks.
`spec/refinement_replay_test.w N M P TENSOR AXIS COORDINATE` also checks the
standalone projection primitive.

Every new input and refined output also enters native **group composition**.
The bounded family groups shared U, V or W factors, scaling the other
two dimensions by 2, 3 and 4. At scales three/four, a bucket dynamic program
chooses disjoint groups of up to six terms. Its exact leaf costs include
singletons and pairs, so its predicted rank cannot exceed pair-only pricing.
Equal prices prefer larger leaves, preserving potentially useful rank-tied
representations. This is optimal only within that fixed-axis bucket family,
not over arbitrary or overlapping groups. Scale two keeps the pair path.
Exact small leaves are built from packaged seeds and disjoint-row sums;
no Ruby/Python or catalog download is used at runtime. The scale-four leaf
projects the packaged 2x4x5/r33 seed, cleans it to rank 27, then replays a
bounded 524,288-move native walk to an independently checked 2x4x4/r26 leaf.
It is cached only after full tensor verification. Immutable leaf-bank
manifests bind all six verified leaves. `MCG1` recipes reference a bank;
pair-only `MFC1` recipes remain readable. Each parent still emits at most
nine fixed-axis recipes, preserving the source-job reservation. Mixed-axis
contexts are offered separately for deferred admission, described below. Parent
markers record recipe identities: re-offering after a leaf change prices
only affected recipes. There is not yet a global reverse-dependency sweep.
`METAFLIP_COMPOSITION_GROUPS=0` selects the pair-only control for new intake;
previously queued grouped recipes still replay exactly.
A price is only a scheduling heuristic: the
expanded tensor passes the full coefficient check before archive admission.
Rank ties remain separate parents and outputs.

`composition/` inside the spool has durable tasks, results and a consumed
cursor for fixed-axis work; `composition/mixed/` has independent journals for
mixed-axis work. Both use the same per-shape best index and hexadecimal
`MFW1` tensor objects in `composition/`. New
task/result pages hold at most 64 bounded records with an atomic rewrite and
payload digest; new recipes need no individual task-index files. Existing
per-record spools remain readable, including partially completed queues and
old leaf recipes. No previous evidence is silently deleted or rewritten.
The digest checks serialization, not the tensor identity. Packed
32-bit limbs support factors through 1,024 bits (16,384 terms), beyond the
live walker's 63-bit limit. At most two expansions run after a refinement
input, and four per idle batch, in the same single low-priority native child.
Each distinct verified composition now also receives **native multiword
matrix cleanup**. It uses sparse scratch initialization and full-limb hashing,
with a 20-million-unit algebra limit. The original object and recipe result
stay unchanged; any strictly smaller output passes another complete tensor
check before entering the shared best/by-shape index. Cached reduced objects
are also fully checked. `composition/cleanup/results/` binds source/result
identities and work status; `compose_wide_status` is 0=idle, 1=fixed point,
2=work-limited, 3=verification-limited, and `compose_wide_saved` is the latest
attempt's admitted saving (not a cumulative total). Limited attempts are not
reported as fixed points or automatically retried with an unlimited budget.
The native path reproduces the earlier **19x27x28
8,169 -> 8,129** cleanup within its limits; this is an integration regression,
not another new bound. See the [wide-refinement audit](tools/NATIVE-WIDE-REFINEMENT-2026-09-10.md).
Verified cleanup outputs now also enter an **automatic wide-transform lane**.
It runs 18 bounded neutral-basis contexts (both column orders, single axes or
two cycles of each axis permutation), followed by strict matrix cleanup.
Every source and distinct admitted basis endpoint gets its coordinate-deletion
family, including same-rank representations. Every output passes a complete
tensor check before indexing; neither a saved hash nor a claimed rank suffices.
The native operators and scheduler have no Python/Ruby runtime dependency.
The [wide-transform study](tools/WIDE-BASIS-PROJECTION-2026-09-10.md) supplies
the retained 8,109 regression; the
[automatic integration audit](tools/AUTOMATIC-WIDE-TRANSFORMS-2026-09-10.md)
documents scheduling, replay and the public-binary tests.
An additional [seeded matrix-basis operator](tools/SEEDED-BASIS-SEARCH-2026-09-10.md)
is available as an explicit library proposal, not a default queue mode. Its
bounded search and composition/projection follow-up found no new retained rank.

Each wide root schedules one finite projection generation. Checked outputs
whose three factor widths fit 63 bits and whose rank is at most 4,096 now
return through an automatic narrow-format feedback queue. Distinct outputs,
including rank ties, enter ordinary refinement and incremental composition;
matching supported campaign shapes can also become live seeds under the
existing near-best policy. Larger outputs remain checked wide archives, not
live u64 seeds or recursively expanded wide roots.
One context runs per scheduler turn; its successors go behind existing work.
Normally wide work receives one in three turns. At 256 pending wide contexts,
composition expansion pauses until this lane drains below that high-water mark.
Existing continuations can temporarily increase the pending count, so 256 is
not a hard queue limit or a disk-byte quota. A basis context makes at most six
20-million-unit axis passes plus one similarly bounded cleanup; output
verification has a separate 20-million-XOR limit. These are work limits, not
wall-clock deadlines. The same single low-priority native child runs all lanes.

`composition/transforms/` stores paged task/result journals and paged
source/context indexes. Appends and consumed-cursor interruptions are replayed
idempotently through full tensor gates. `wide_transform_*` exposes submitted,
completed, pending, failures, status and latest term-count delta; pending counts
materialized contexts, not all future continuations. Status is 0=idle,
1=context completed, 2=algebra-limited, 3=verification-limited. Limited output
is not labeled a fixed point, and verification-limited output is not admitted.
A projection's delta compares different shapes, not a best-known-rank gain.
`METAFLIP_WIDE_TRANSFORMS=0` disables new intake and pauses existing wide work
without deleting it. Corrupt tasks remain pending with a visible error.

The child-owned `composition/feedback/` outbox binds both full tensor formats.
Only the main coordinator writes narrow intake tickets and acknowledges this
outbox. It rechecks both objects and their exact termwise conversion, consumes
at most one record per 250 ms, and pauses at eight pending refinement jobs or
composition backpressure. Excess work stays durable; this is not a disk quota.
`METAFLIP_WIDE_FEEDBACK=0` disables publication and pauses consumption without
discarding the archive. `wide_feedback_*` reports submitted/completed/pending,
failures, oversized/unsupported live seeds, and actual live `seed_uses` (not
merely queue consumption). A consumed descendant of a *different* live-seedable
shape (square 2x2..7x7 or an allowlisted rectangle) is re-verified as a full
tensor and spooled as a bare rank-header scheme into that shape's
`banks/gf2/<n>x<m>x<p>/feedback/feedback_00..07.txt` under the shared state
root (`wide_feedback_offered`); a full spool keeps the lowest ranks, ties by
lower body SHA-256, so replay is a no-op and the slot set stays finite. The
next non-naive campaign for that shape admits those slots only through its
existing exact loader (square near bank; rectangular side archive when that
archive is enabled) and reports `wide_feedback_loaded`. No allowlist widens
and no rank-record claim follows from a spooled slot. See the
[feedback and square-restriction audit](tools/WIDE-FEEDBACK-2026-09-11.md).

`compose_submitted/completed/pending/failures` sum the two primary lanes, separately from
source refinement. `compose_deferred` counts mixed parent/context references
not yet admitted as recipes; the TUI also shows this deferred work.
The primary lanes alternate on their turns while both have work. Each uses a bounded 128-ticket
priority window. It favors a smaller
predicted rank relative to the current verified per-shape best (or the naive
rank when absent), with cheaper-rank/older-ticket tie breaks. Every fourth
completion in that lane serves its oldest pending ticket, so new proposals
cannot starve old work in a non-failing queue. This is ordering, never
dominance pruning.
`METAFLIP_COMPOSITION_FIFO=1` selects the FIFO control. `MFC_RESULT2` records
bind completion order to original ticket IDs; a small checksummed completion
mask supports restart without duplicating or losing out-of-order work. Legacy
FIFO records remain readable. An interrupted result/state/cursor commit is
replayed through the full tensor gate, not accepted from its hashes alone.
An invalid or over-budget selected recipe stays pending with an `error` file;
automatic composition pauses while ordinary flipping continues.

Refinement expansion reserves space for the fixed-axis recipes of its entire
bounded output family before writing derived objects or recipes. Mixed-axis
parent/bank references are deferred, then expanded into recipes only as shared
queue capacity becomes available. The default pending-composition
limit is 4,096 (`METAFLIP_COMPOSITION_PENDING=1269..1000000`; `0` selects the
unlimited control). When insufficient space remains, original source tickets
stay queued and the child drains composition even while source jobs await
refinement. Mixed admission yields freed capacity to a blocked source job.
`refine_blocked` and `compose_limit` expose this backpressure;
the TUI also shows `blocked`. It is not counted as a failure or a completion.
The setting is fixed at startup; invalid values use the default. Existing
over-limit queues drain without deleting evidence. The limit applies to
materialized pending recipes across both primary lanes, not the separately
throttled transform lane, offline tools or manually edited spools. There is
still no disk-byte quota: unprocessed originals,
deferred parent references and completed tensor artifacts remain retained.
A composition error can also hold up new expansion.

The regression **4x8x4/r94 → 4x7x4/r85 → 12x7x12/r651** now runs through
native queue intake and expansion (12x7x12 is a permutation of 7x12x12).
The rank-26 scale-four leaf also gives **16x7x16/r1132**, down from the native
rank-28 leaf's 1,208. These reproduce known local constructions, not new records.
Larger groups also reproduce **2x2x8/r28 → 8x8x8/r329**, versus the pair-only
price 364, without changing the parent. Eighteen leaf tensors and 90 composed
outputs have independent full tensor and term-set regressions in
`spec/group_composition_parity_test.py`; grouped queue upgrade, corrupted
dependencies and selective repricing are covered by
`spec/group_composition_queue_test.py`.
The external parent is test-only, not redistributed. Replay with
`spec/composition_queue_test.py NATIVE_TEST_BINARY [EXTERNAL_4x8x4]`.

This is still a bounded family, not an exhaustive basis/packing search.
Larger elementary grids, changing-leaf dependency propagation, recursive wide
composition and automatic cross-shape campaign dispatch remain follow-up work.
The native `composition/mixed_groups.w` engine supports disjoint shared-factor
groups of up to four terms from different axes in one construction, using
the existing verified 22-leaf bank for all 27 scale triples in `{2,3,4}^3`.
Only groups with actual bank witnesses are eligible. It starts with the
mixed-pair plan, then solves components of at most 16 terms; larger or
probe-limited components retain their original pair plan. The default
`composition/mixed_grids.w` pass additionally packs disjoint 2x2 grids in
U/V, U/W or V/W factor classes together with those groups. It validates all
four distinct cells and their complete linear maps, using only available
bank leaves. An oversized or probe-limited grid component keeps the previous
group plan; contexts without a useful grid leaf skip the additional solve.
This runs
automatically for every distinct verified input and
refined parent, including rank ties. An immutable parent/bank reference yields
two separately versioned batches: up to 27 `MFM3` recipes for `{2,3,4}^3`,
and up to 27 `MFM6` recipes with exactly one scale coordinate equal to one
and the other two in `{2,3,4}`. Admission still visits at most 27 contexts
per cold batch under the
shared pending limit. Recipes fix a 50,000-state pair budget plus 50,000 group
probes (including memo hits), plus 50,000 grid/group probes. Failed rectangle
probes also consume the budget. The recipes replay
the parent, leaf bank, price and full tensor check before admission. Supported
contexts without pair savings are retained too. Input ranks above 512,
factor widths above 1,024 bits or predicted outputs above 16,384 terms are
outside this bounded family; skipping those contexts is not a verified
tensor completion.

`METAFLIP_COMPOSITION_MIXED=0` disables new mixed intake without abandoning
already queued work. `METAFLIP_COMPOSITION_SCALE_ONE=0` disables new offers
of the second domain without abandoning its queued work. Unit-coordinate
leaves are literal naive tensor witnesses; optional leaves exceeding the
63-bit positive-mask limit are unavailable, not assigned an estimated price.
The immutable 22-leaf bank and all old recipe identities stay unchanged.
`METAFLIP_COMPOSITION_GRIDS=0` selects group-only `MFM2`/`MFM5` offers.
`METAFLIP_COMPOSITION_MIXED_GROUPS=0` selects pair-only `MFM1`/`MFM4` offers.
The first number is the old domain, the second the scale-one domain.
Old parent tickets keep their exact algorithm and domain when resumed;
re-offering an old parent under the new version creates separate contexts.
A changed bank identity is repriced when its parent is
re-offered; old recipes remain reproducible. There is no full dependency
rescan. Restart, stop, exact-gate rejection, shared-cap and deferred-only
coordinator checks are in `spec/mixed_composition_queue_test.py`. See
[Automatic scale-one composition](tools/AUTOMATIC-SCALE-ONE-COMPOSITION-2026-09-09.md)
and `spec/scale_one_composition_test.py` for the added witness/domain and
recovery checks. Single-axis-only expansions (two scale coordinates equal
to one) are supported by direct composition but not yet this automatic
batch; no dominance argument discards them. See
[Automatic mixed composition](tools/AUTOMATIC-MIXED-COMPOSITION-2026-09-09.md)
for the integration audit and its 1,620 fully verified outputs across 153
canonical shapes (zero new local bounds), and
[Native mixed-axis pairs](tools/NATIVE-MIXED-PAIRS-2026-09-09.md)
for the engine's independent 891-case comparison. The
[mixed-group audit](tools/NATIVE-MIXED-GROUPS-2026-09-09.md) covers the new
bounded family: 876 lower construction prices in 7,803 distinct retained
parent/scale cases, but no new local bound or world-record claim.
The [multi-grid integration audit](tools/NATIVE-MIXED-GRIDS-2026-09-09.md)
reproduces the externally found 8x10x14/724, 8x15x21/1548 and 12x15x14/1542
constructions in the native pipeline. These are integration regressions,
not additional discoveries.
Wide outputs are exact archived witnesses, not yet live wide-worker seeds.
See the [native integration audit](tools/NATIVE-REFINEMENT-2026-09-08.md) for
the first refinement milestone, and the
[native composition audit](tools/NATIVE-COMPOSITION-2026-09-08.md) and
[paged queue/leaf upgrade audit](tools/NATIVE-COMPOSITION-PAGES-2026-09-08.md)
and [priority scheduling audit](tools/NATIVE-COMPOSITION-PRIORITY-2026-09-08.md)
for these extensions. With grouped composition enabled, the matched
105-recipe regression reaches r1132 on completion 4 rather than 48, and
r651 on 8 rather than 47; both schedules end
with the identical verified output set. This is one workload, not a universal
performance or efficacy claim.
The [backpressure audit](tools/NATIVE-REFINEMENT-BACKPRESSURE-2026-09-08.md)
covers bounded pending work, restart, the public canary and subsequent searches.
The [larger-group integration audit](tools/NATIVE-GROUP-COMPOSITION-2026-09-08.md)
covers the leaf bank, independent replay and frozen-parent screen.

Alternatively, let Bit preserve the executable, runtime worker sources, and
assets as one relocatable build tree:

```sh
bit build --release
./build/bin/metaflip --self-test --no-gpu
```

Run a CPU-only smoke test before starting a long campaign:

```sh
bin/metaflip --self-test --no-gpu
```

### Optional Core ML ranking experiment (macOS)

Core ML can advise a fraction of natural shoulder-seed renewals while CPU and
Metal search continue. It never supplies moves or bypasses exact GF(2)
verification. This is off by default, supports 5x5 only, and is not a demonstrated
record-finding improvement. Two bounded snapshot pools prevent recycled bank
slots from changing a candidate while inference is pending. Stale, malformed,
nonfinite, timed-out, or inexact recommendations are rejected; helper failure
leaves the ordinary search running.

Train only on local, exact-verified rollouts (Python with NumPy and coremltools
is needed for export; no model or data downloads are performed):

```sh
mkdir -p build/coreml/candidates
tungsten compile spec/coreml_ranker_dataset.w --out build/coreml/dataset --release --native
build/coreml/dataset --out build/coreml/dataset.jsonl --bank-dir build/coreml/candidates \
  --origins 12 --candidates 24 --steps 4096 --max-ms 30000
python3 tools/train_coreml_ranker.py build/coreml/dataset.jsonl --out-dir build/coreml/model
swiftc -parse-as-library -O tools/coreml_ranker.swift -o build/coreml/helper
bin/metaflip --tensor 5x5 --coreml-model build/coreml/model/ranker.mlpackage \
  --coreml-helper build/coreml/helper --coreml-workers 1 --coreml-compute cpuOnly
```

`--coreml-workers` controls host preprocessing concurrency, **not** reserved CPU
cores or Neural Engine cores. `cpuAndNeuralEngine` excludes Metal and requires
ANE-preferred operations in the loaded execution plan; it fails closed if
there are none. The first measured model was ANE-supported but CPU-preferred,
and an Instruments trace showed no ANE execution. Use `cpuOnly` explicitly for
that model. Device availability or model support alone is not acceleration.

`METAFLIP_PHASE_TIMING=1` emits worker/barrier/coordinator timings;
`METAFLIP_CPU_EPOCH_MS=250` overrides the batch target without rebuilding.
`METAFLIP_CPU_SCHEDULER=sync|async` selects the square fleet's CPU scheduling
mode. The default remains `sync`: matched runs of the improved coordinator did
not show a consistent throughput benefit from async, despite higher occupancy.
Async lanes publish into fixed, coordinator-owned snapshots and restart after
their own exact intake and lease renewal, overlapping GPU harvesting and status
work. Rank-drop migrations, explicit resets, and shutdown still drain pending
epochs. No speculative endpoint is discarded, and there are exactly two state
buffers per CPU lane. `--rounds` stops after every lane has completed at least
that many epochs; fast lanes can complete more before the final drain.
The phase record's `barrier_ms` is only the completion wait in async mode, not
a fleet-wide barrier. `coordinator_ms` overlaps worker execution; it must not
be interpreted as idle CPU time. `leases_ms` separates local lease renewal from
global `reseeds_ms`; `completed` and `inflight` expose the pipeline occupancy.

`tools/bench_cpu_epochs.rb` performs bounded isolated cadence or CPU/Core ML
allocation sweeps, logs process/GPU samples and model timings, and independently
verifies final tensors. Its `--allocations 16:0,16:1,15:1,14:2,12:4` means
CPU-search workers : helper preprocessing workers; `0` disables the model.
Provide `--binary`, `--expected-sha`, `--runtime-root`, `--output`, and, for
model runs, `--model`, `--helper`, and `--compute cpuOnly` explicitly.
For a matched scheduler comparison use `--schedulers sync,async,async,sync`.
To compare a preserved pre-change binary, supply `--baseline-binary` and
`--baseline-sha`, then use `--schedulers baseline,async,async,baseline`.
Each trial has isolated state, an independent final GF(2) check, process/GPU
samples, bounded descendant cleanup, binary hashes, and an RSS-growth estimate.

The frontier archive reuses a bounded pair-distance cache. It checks the full
rank, dimension, and ordered factor triples on every access, so in-place
reseeding invalidates affected rows without trusting a digest for freshness.
Admission decisions and tie-breaking are unchanged from the exhaustive policy;
the cache does not replace any tensor verification gate.
The GPU Pareto bank also copies endpoints only after admission and recycles
evicted buffers; rejected endpoints no longer allocate full CPU search states.

The measured scheduler and allocation results, exactness checks, limitations,
and replay commands are in [the follow-up profile](tools/PROFILE-SCHEDULER-2026-09-06.md).

The package also ships a compile-time layout check and an optional one-epoch
Metal integration check:

```sh
tungsten compile spec/package_layout_test.w --out /tmp/metaflip-layout-test
/tmp/metaflip-layout-test

tungsten compile spec/gpu_smoke.w --out /tmp/metaflip-gpu-smoke
/tmp/metaflip-gpu-smoke "$PWD/lib/metaflip"

tungsten compile spec/metallib_runtime_fallback_smoke.w --out /tmp/metaflip-msl-fallback-smoke
PATH="$PWD/spec/fixtures/offline-metal-failure:$PATH" /tmp/metaflip-msl-fallback-smoke "$PWD/lib/metaflip"

tungsten compile spec/fixed_rank_pocket_strategy_test.w --out /tmp/metaflip-pocket-test --release --lto
/tmp/metaflip-pocket-test

tungsten compile spec/generic_search_test.w --out /tmp/metaflip-search-test --release --lto
/tmp/metaflip-search-test

tungsten compile spec/finite_map_search_test.w --out /tmp/metaflip-finite-map-test --release --lto
/tmp/metaflip-finite-map-test

tungsten compile spec/proximity_orbit_gain_bench.w --out /tmp/metaflip-proximity-gain --release --lto
/tmp/metaflip-proximity-gain

tungsten compile spec/proximity_projected_cubic_bench.w --out /tmp/metaflip-proximity-cubic --release --lto
/tmp/metaflip-proximity-cubic 1 8 exact 1000

tungsten compile spec/seven_by_seven_d3492_fertility_bench.w --out /tmp/metaflip-d3492-fertility --release --lto
/tmp/metaflip-d3492-fertility
```

## Proof library

`use metaflip` exposes a caller-owned incremental CDCL solver and an exact
transpose-involution (`psi`) quotient for GF(2) matrix multiplication tensors
of shape `<n,m,n>`. The solver uses one flat `i64[]` arena and rebuilds its
decision heap only through the highest variable actually referenced, so spare
capacity does not silently become search state. It supports clauses, XORs,
assumptions, failed-assumption cores, conflict budgets, and clause marks.

The psi solver models a rank `2*pairs + fixed` invariant decomposition. Its
compact encoder keeps one row from every complete coefficient-cell orbit and
cancels conjugate-pair products only on genuinely fixed cells. Pair
orientation and interchangeable-generator ordering are sound symmetry
breakers; whole-matmul solves additionally use a coordinate anchor and the
`n=2` fixed-cell rank consequences. SAT results are expanded and exhaustively
checked against every coefficient before the API returns them.

```w
use metaflip

out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
meta = i64[16]

# The Strassen psi cell: rank 7 = 2*2 conjugate terms + 3 fixed terms.
rank = metaflip_proof_psi_solve(
  2, 2, 2, 3, 400000, 1,
  out_u, out_v, out_w, meta
)
```

For independent checks, `metaflip_proof_psi_encode_full_matmul` retains every
coefficient row, while `metaflip_proof_psi_encode_quotient_matmul` exposes the
exact orbit quotient over a caller-owned CDCL state. Focused release/LTO
regressions live in `spec/proof_cdcl_test.w` and `spec/proof_psi_test.w`.

## Domain-neutral exact search

`use metaflip` also exposes `Metaflip:Search`. It retains the production
fleet's exact-gate and adaptive-diversity architecture without assuming a
field, tensor, score meaning, or candidate representation. A domain adapter
provides three one-argument closures:

- a portfolio of strategies taking `Metaflip:Request` and returning a
  `Metaflip:Proposal`, a bounded `Metaflip:ProposalBatch`, a costed
  `Metaflip:NoProposal`, or `nil`;
- an exact verifier returning `Metaflip:Assessment` or `nil`;
- a snapshot function that makes an independent stored copy of a candidate.

Only exact assessments can enter the bounded descriptor archive, improve the
global best, or reward a strategy. Strategies may use arbitrary heuristic,
parallel, or accelerator work internally; proxy scores are intentionally not
part of the coordinator API. Exact objectives are lexicographic and each
component may be maximized or minimized.

```w
use metaflip

snapshot = -> (state) [state[0], state[1]]
verify = -> (state)
  result = nil
  if state[0] >= 0 && state[1] >= 0
    # Maximize x, then minimize y; x%8 is the diversity niche.
    result = Metaflip:Assessment.new([state[0], state[1]], state[0] % 8,
      state[0] * 1000000 + state[1])
  result
mutate = -> (request)
  parent = request.best || [0, 0]
  Metaflip:Proposal.new([parent[0] + 1, parent[1]], 1)

search = Metaflip:Search.new([mutate], verify, snapshot, [1, -1],
  {capacity: 32, seed: 7})
search.seed([0, 0])
search.run(1000)
<< search.best_scores
```

`Proposal.cost` is a positive, adapter-defined exposure unit, allowing the
portfolio to compare a cheap local mutation with a batched solver or GPU
strategy. A strategy that performed nontrivial work without finding a
candidate may return `NoProposal.new(cost)` so exploration is charged by the
same exposure scale; plain `nil` remains a unit-cost miss. Descriptor and
identity equality use ordinary Tungsten `==`, so
they may be integers, strings, symbols, or immutable value objects. An
identity of `nil` disables cross-niche deduplication. The focused non-GF(2)
regression is `spec/generic_search_test.w`.

`ProposalBatch` is the exact candidate-selection primitive for coordinate
sweeps, repair neighborhoods, and accelerator harvests. Every member is
verified and admitted separately; the arm receives one pull, the sum of all
member costs as exposure, and only post-gate valid/novel/improvement credit.
The first exact candidate in an unseeded run establishes the baseline and does
not give its arm an order-dependent improvement or novelty windfall. Keep
batches bounded: they expose alternatives to the archive, not a substitute for
streaming a very large campaign.

`step` returns a telemetry event for interactive callers. `run(steps)` avoids
allocating those per-step events and returns only the snapshotted best state.

`spec/proximity_orbit_gain_bench.w` is a retained historical-gain test rather
than a toy optimizer. Its external adapter encodes the exact integer ledger
behind the Proximity Prize upper track's 512-fibre improvement, seeds the
previous 139502-agreement result, and asks the generic coordinator to recover
the verified 512/272/14 parameters (139775 agreements). It also rejects the
later 1024/136/6 counting obstruction and compares the adaptive portfolio with
uniform sampling under equal exact-check budgets. Lean proof generation and
submission translation deliberately remain outside Metaflip.

### Finite-map fibre adapter

`Metaflip:FiniteMapDomain` supplies a reusable exact adapter for rational maps
on a finite subset of a prime field. It computes the complete image histogram,
exact-size fibre coverage, capped collision mass, overfull fibres, and poles.
The built-in strategy portfolio mutates numerator and denominator coefficients;
callers can pass structured algebraic strategies to `domain.search_with` while
retaining the same verifier and archive.

```w
points = []
17.times -> (i) points.push(i)
domain = Metaflip:FiniteMapDomain.new(points, 17, 2, 3, 1)
square = Metaflip:PrimeRationalMap.new([0, 0, 1], [1])
profile = domain.profile(square) # eight exact 2-fibres, plus zero

search = domain.search({capacity: 64, seed: 9})
search.seed(square)
search.run(10000)
```

Coefficients are constant-first. Candidate identities are normalized under a
common nonzero field scalar, so equivalent numerator/denominator presentations
deduplicate. By default any pole on the input set is an exact rejection;
`{allow_poles: true}` keeps poles as a minimized score component instead. The
adapter supports primes through `3037000499`, which keeps every reduced Horner
product inside signed 64-bit arithmetic. Its focused regression is
`spec/finite_map_search_test.w`.

For a requested fibre size `d`, locator strategies construct a monic degree-`d`
polynomial with a chosen zero fibre. When both degree bounds permit it, paired
locators use `A/(A+B)` for disjoint root sets, guaranteeing finite fibres at
zero and one before the exact pole/profile gate. Locator flips now use the
archive parent first, so retained basins are actually explored, and
`{locator_batch: k}` emits up to `k` root-preserving alternatives through a
`ProposalBatch`. `{diversity_bins: n}` adds a stable scalar-normalized
coefficient bucket to the metric descriptor; use it to retain plateau basins,
and lower `novel_reward` when those identity buckets are diversity only rather
than mathematical novelty.

`spec/proximity_projected_cubic_bench.w` applies these operations to the actual
KoalaBear `mu_512` labels. Its radix index exhausts all `C(512,3)=22,238,720`
monic split cubics and proves that a cubic polynomial has at most one exact
three-fibre there. Paired rational locators immediately improve the matched
coefficient baseline from zero to two constructed fibres. The retained search
also contains an in-place coordinate sweep and a collision-equation
repair: an observed double fibre can be promoted by solving all one-/two-root
repairs before paying for another full histogram. This benchmark discovers and
exact-checks maps only; translation to any proof or submission stays outside
Metaflip.

## Run

Square campaigns select their tensor explicitly:

```sh
bin/metaflip --tensor 3x3
bin/metaflip --tensor 5x5 --secs 3600
bin/metaflip --tensor 7x7 --no-gpu
```

Independent square-fleet shards can use `--seed-nonce N`.  Nonce zero is the
default and preserves the historical seed choices and RNG trajectory exactly;
different nonzero values phase the finite +1/+2 algebraic-escape identities,
apply distinct exact coordinate embeddings to density-normalized seeds, rotate
tied seed-bank choices, and mix every CPU island's initial and restart streams.
This avoids duplicating both shoulder banks and later walks when the same
command is launched in several processes.

The same `--seed-nonce N` control applies to one explicit rectangular
`--tensor`. It phases every rectangular island's proposal stream while nonce
zero preserves the historical trajectory. Advanced sharded launchers may
also pass `--rect-door-ticket N` to rotate a one-lane or multi-lane shard
through checked-in side doors independently of the RNG nonce. The adaptive
`--rect` portfolio owns both schedules itself and therefore rejects manual
nonce overrides. Salted profile shards load the exact eight-slot side archive,
checkpoint their barrier-stable island bests every fifteen minutes (or shortly
after a fleet-leader adoption), and save the final live shoulders on process
exit. A reclaimed spot tranche therefore retains useful nonleader endpoints
instead of preserving only its fleet best. Explicit `--seed` experiments
remain isolated from that archive.

Wide salted shards reserve enough lanes to touch every available side door,
then split surplus width between the fleet best and side exploration. In the
standard `J64` six-leaf campaign this is 32 independent leader streams and 32
balanced side-door streams, rather than concentrating 63 lanes on a handful
of shoulders.

For CPU fleets of eight or more walkers, `--steps` is the nominal worker chunk
rather than a forced coordinator cadence. After the first measured epoch,
fleets of 8--32 walkers adapt toward about 250 milliseconds of parallel work;
wider fleets adapt toward about three seconds. Tiny fleets retain the
historical cadence. The adaptive range remains bounded, and status files
report `cpu_seed_nonce`, `cpu_epoch_target_ms`, and the live
`cpu_epoch_steps_min`/`cpu_epoch_steps_max` range so cloud campaigns can audit
both diversity and cadence.

The packaged 7x7 campaign starts from the exact rank-247, density-3094
frontier. Its d3096 parent came from dynamic exact syzygy mining over a live
term window and bounded one-factor XOR neighbors. A subsequent NUMA-local CPU
shard found a four-flip path to d3095 after about 735.3 billion moves. Replaying
the legal path exposed that its first three flips already reach d3094, while
the fourth costs one density bit; the packaged endpoint therefore omits that
last move. It is a three-term exchange at term-support distance six from
d3096. Metaflip keeps d3094 as the hot default while retaining the nearby
d3096 parent and structurally distant rank-247 restart doors. Every endpoint
was checked against all 7^6 target coefficients; d3094 additionally passed
independent pure-Tungsten and host-side verifiers before packaging.

The active affine-code frontier slot is now a second exact rank-247/d3094
support, without changing that hot default. Runpod pod `aack78ni07p1uh`
produced it at epoch 257/group 8177 from source commit
`1dfc4321f964a0ca4eca75e8c0870f8692d565b0`. It is one three-term exchange
(support distance six) from the packaged epoch-3306 d3096 affine-code parent,
but support distance 396 from the incumbent d3094 scheme. In 48 canonicalized
matched four-million-move continuations it tied the incumbent in every trial
and beat the parent 48/0/0. Metaflip therefore replaces only the affine-code
frontier/source-4 slot and keeps the d3096 parent as explicit replay. The raw
certificate SHA-256 is
`ddf710feced82ece388d9e368f9ad4bcf4da08d0583c4b17ab34a8a5e1accb71`;
its order-independent term-multiset SHA-256 is
`d71bbeb41d5da88264475eb412baca85d099764fa3a1fce9474cffc78b7cfee8`.

The structurally distant C013 branch also retains an autonomous fixed-rank
pocket closure at rank 247/d3496. Starting from d3554, a target-free greedy
word closes at densities `3544,3534,3524,3514,3506,3498,3496`; its two deepest
tickets require local `+10` and `+9` barrier edges. The later d3492 CUDA child
is four support terms away. Final Runpod triage then found a rank-247/d3486
continuation endpoint in three independent 4M-move trials (4/15/21; seeds
`718917`, `1870936`, and `2499310`). It is support distance 20 from d3492 and
42 from its d3542 source. A direct continuation was locally terminal, so d3486
replaces only the active C013 basin slot; d3492 and d3496 remain explicit
provenance and the earlier d3546 barrier child remains an active replay
shoulder. The raw, order-independent term-multiset, and D3/reversal SHA-256 are
`dfab762a6150c274b670f67f6169d3635c32974c0be106482717b94fae149b05`,
`52284f28e3886fe20b848ddd81d57993dbd1566de11c13cce8875c4729ffbef3`,
and `4873e956b1f3df815c250ab99fceb4ee9f3dd18c230fea8b5985e9f4817952ec`.
Its coarse MAP descriptor collides with the affine d3094 co-leader, so the
lower-density affine scheme owns that MAP niche while d3486 remains a distinct
frontier/archive door. None replaces the d3094 hot leader.

The exact Runpod epoch-1965/group-6417 d3542 certificate now owns the single
cold `ffp_low_quota_seed_paths(7)` slot. Across 24 canonicalized matched
four-million-move continuations it beat the former d3538 low-quota source
24/0/0 and the former active d3492 endpoint 23/0/1, while producing the same
d3486 endpoint three times. It is support distance 66 from d3538 and 62 from
d3492. That fertility makes it a better CUDA source-3 and cold restart door,
but d3486 itself remains the production endpoint. The older d3538 certificate
is retained for explicit replay. The low-quota inventory remains one item and
therefore still receives exactly one seventeenth of the frozen-source
escape/partial-automorphism schedule at the default 16-source archive size.
Raw, order-independent term-multiset, and D3/reversal SHA-256 are
`bc0d913f34d0b733436059e16775bbff3c8f29e3306bd5b8e29de4f05a05b676`,
`6a54c3e5388784485afa3a10814a9e41658ff7456c339c3e01e1c487fe6e4f6c`,
and `dbd111c632e27812ddddac7300e6d4842a68340248842dce65c825f8eb7c9a24`.

That discovery also produced a reusable exact move, **support-component
peeling**. For two exact parents `A` and `B`, Metaflip forms `D = A xor B` and
joins changed terms only when their rank-one tensor supports overlap on all
three axes. Separate graph components occupy disjoint tensor cells, so each
component of the zero tensor `D` is itself a zero relation. The bounded worker
tests every proper component from both parents, with full coefficient gates on
the parents, relation, materialized children, and winner. The live d3096/d3095
delta has ten terms split `6+4`; peeling the six-term component recovers d3094
directly. Same-rank density improvements receive this cold intake pass at
`d<=64`, while the one-child differential pool uses the same move before its
general nullspace fallback. Ordinary move loops and archive novelty policy are
unchanged; only that worker's launch floor is reduced from distance 12 to 6.

The 7x7 coordinator also runs a low-duty exact partial-automorphism portfolio.
Every fifteen seconds it rotates across the frozen record-rank frontier and a
per-source elementary-generator cycle; `--seed-nonce` phases both dimensions,
so three independent shards begin in disjoint generator arcs. Each endpoint is
fully gated before intake. The max-min frontier archive and MAP-Elites then
make independent admission decisions, preserving a useful MAP niche even when
it is too close to improve the sixteen-state archive. Live status exposes
`partial_auto_attempts`, `partial_auto_hits`, `partial_auto_archive`, and
`partial_auto_map` so sharded campaigns can verify useful intake directly.

The adaptive pool now includes three bounded host-side exact workers alongside
its Metal kernels: `mode-cpals` (one-factor affine re-solve), `debt-mitm`
(direct 6-to-4 and split-assisted closing), and `dynamic-syzygy`. Each costs
one logical 32-lane quantum and rotates under the same contextual policy;
dynamic syzygy is currently 7x7-only because that is its only demonstrated
plateau win. Adaptive exploitation is normalized by measured 32-lane/100-ms
exposure, including failed and stale children, while cold coverage and the
hard one-in-four rotation preserve diversity. The strongest planted-debt move,
block-interior refactoring, is a permanent selector inside both exact
`span-refactor-3` and
`span-refactor-4`: one quarter of their neighborhoods target composition
seams, including the 7x7 4+3 cut, without duplicating the expensive join or
adding a fourth physical pool slot.

One CPU parameter-racer arm now runs a bounded autonomous fixed-rank pocket
closure at lease start. A cheap ordinal-1 prefix is followed by complete
strict-gain rescans of the current ticket surface. Every ticket keeps pocket
size/depth at most five, a 512-state arena, and a `+12` uphill-edge ceiling;
the lease caps the whole word at eight adoptions, four prefix attempts, five
full rounds, and 64 tickets per round. The C013 prepass reaches the same d3496
endpoint in 31.6M rather than 50.7M proposals. Every adopted endpoint receives
a full tensor gate; misses, invalid bounds, and failed candidates preserve the
exact source. Proposals count toward exposure and setup gains toward adaptive
reward, so the cold closure uses one racer arm without changing the TUI or the
ordinary per-move hot path.

A second bounded racer arm uses **alternate-axis retry**.  When a randomly
chosen first term has no partner on its selected axis, that arm alone reuses
the term and probes the other two axes before declaring the proposal dead.
Matched-wall native trials improved accepted flips per second by 31% on 3x3,
36% on 5x5, and 19% on 7x7 while retaining distinct exact endpoints and
comparable support distances.  It remains one adaptive arm: ordinary CPU
islands keep their unchanged fast path and RNG trajectory, while a cold
incidence check sends provably edge-free racer states back through baseline.

The square k-XOR pool is collision-complete: when several table tuples share
the requested 128-bit fingerprint, it advances through tuple ordinals until
every disjoint candidate has passed the exact local gate. The `8->7` path also
decodes its three-term table keys with the correct radix before overlap
filtering. Empty-fingerprint rounds still require one dispatch; extra work is
paid only when a join actually has multiple candidate tuples.
After live terms and reconstructed split parents are protected, the bounded
candidate tail traverses its factor Cartesian product with a full-cycle
coprime permutation. Short pool prefixes therefore sample all three factor
axes instead of exhausting W while pinning the first U/V pair; an unbounded
pass remains exhaustive and duplicate-free.

The executable normally locates `lib/metaflip/` beside its installed build
tree. `--runtime-root PATH` or `METAFLIP_RUNTIME_ROOT` can select an unpacked
bit explicitly. `--asset-root`, `--repo-root`, `METAFLIP_ROOT`, and
`METAFLIP_ASSET_ROOT` remain compatibility aliases for one release.

The same binary accepts the bundled rectangular profiles using full labels
such as `2x2x5`, `2x2x6`, `2x2x9`, `2x5x6`, and `4x5x7`. `--rect` runs the adaptive multi-shape
portfolio. Thread and lane counts have hardware-aware defaults; use `-J` and
`--gpu-walkers` only when an experiment needs fixed allocation. The generic
portfolio default is 16 base rounds per allocation epoch. Explicit
`--rect-epoch-rounds N` values from 1 through 256 are accepted for bounded
experiments and single-shape cloud parents; raising the ceiling does not change
the interactive default. Fast children use bounded multi-round fills while
slower base quotas run, including during GPU startup. `METAFLIP_RECT_FILL=single`
restores one-round fills for comparisons; `batch` is the default. The
[matched fill measurements](tools/PROFILE-SCHEDULER-2026-09-06.md#rectangular-fill-scheduling)
also document exact verification and the limits of the performance claim.
Rectangular CPU islands continue in short, bounded batches while their GPU
epoch is in flight. `METAFLIP_RECT_CPU_GPU=barrier` restores the old wait;
`overlap` is the default. This does not change CPU-only quotas or the square
fleet scheduler. The status fields `cpu_followup_batches` and
`cpu_followup_moves` expose the extra work, which is included in `cpu_moves`.
The [matched overlap comparison](tools/PROFILE-SCHEDULER-2026-09-06.md#cpu-work-during-gpu-epochs)
measured higher throughput, not better tensor ranks.
The current Metal throughput knee is 8,192 walkers
with 40,000 trajectory steps per
scheduler epoch. Adaptive rectangular scheduling keeps each active child at
that occupancy floor and rotates shapes between epochs; larger explicit lane
budgets can run one additional shape per 8,192 walkers. `--gpu-walkers` and
`--gpu-steps` override those defaults. The default portfolio includes the
explicit `2x2x7`, `2x2x8`, and `2x2x9` fronts; each has exact `R`, `R+1`, and
`R+2` restart strata, and the rank-24, rank-27, and rank-31 targets are
evaluated independently. The `2x2x7` leader is the exact rank-25/density-128
scheme found by the rectangular CPU portfolio; its former density-132 catalog
leader remains a support-distance-42 rank-25 restart door.

Rectangular portfolio children and explicitly salted profile shards retain
eight exact-gated side doors at ranks `R`, `R+1`, and `R+2`. Slots are selected
for structural class and term-set
distance as well as rank, so restarts preserve genuinely different basins
instead of nearby copies of the leader. When full, the eight-slot archive lets
a 15-lane child start from ten distinct sources on profiles with one built-in
frontier door; a controlled 4x6x7 continuation retained all eight distinct
structural signatures with no measurable throughput loss. Metal alternates
fleet-best epochs with the exact door
scheduled for that shape's CPU host, including one-host portfolio allocations;
this prevents a broad portfolio from silently sending every GPU epoch back to
the leader. Periodic side-door writes happen only at the common quiescent
barrier, reconstruct prior disk slots before max-min selection, and never
rebase a live island. CPU islands likewise retain their OS threads for the campaign
lifetime and reload their coordinator-owned state slots after each round
barrier, avoiding repeated thread allocation without weakening sticky-door
independence. One additional coordinator-resident block-interior probe snapshots
a rotating island at the barrier and runs concurrently with the ordinary
tranche. It recovered planted +1 debt across the tested square and rectangular
profiles and exposes exact rank-neutral doors on real rectangular plateaus;
its 1..16-round cadence adapts to measured probe/CPU wall time so a large span
join cannot become the portfolio barrier. The low-cadence 5-to-4
meet-in-the-middle lane runs
concurrently with CPU islands and Metal walking; its output is joined and
fully verified at the epoch barrier. Every shape in the default mix now has a
specialized cal2zone worker, including `4x4x6`, `4x5x6`, and the full-width
i64 `4x5x7` lane. The non-default but high-leverage `4x6x7` frontier also has
an eight-walker i64 worker, so explicit high-impact portfolios can allocate
Metal breadth to its 42-bit middle factor instead of falling back to CPU-only
search. 5-to-4 MITM is also enabled for the validated small
`2x2x6` profile. Rectangular status
child files report block-interior attempts/exact endpoints/drops/cadence;
portfolio files report CPU moves, GPU moves, MITM attempts/pairs/time, and
MITM failures separately per shape and in total, including work completed by a
segment that later exits unsuccessfully.

Each bounded portfolio segment runs in a disposable OS process. The child
keeps its islands and accelerator helpers persistent within the segment, then
the kernel reclaims its complete state arena at the exact epoch boundary.
This process boundary is important on long, high-core-count runs: Tungsten's
native arrays are campaign-lifetime allocations, so repeatedly constructing
shape campaigns in coordinator threads would otherwise retain every completed
epoch until the whole portfolio exited. Within each square or rectangular
coordinator, serial exact-admission gates reuse one caller-owned parity slab;
compatibility APIs still allocate when a standalone caller does not supply one.

Use `--no-gpu` on machines without a supported GPU. The CPU fleet requires a
64-bit Tungsten target. GPU acceleration currently requires macOS on Apple
Silicon and runtime Metal shader compilation. Discoverable `metal` and
`metallib` tools are an optional faster cache tier: Metaflip prepares an
offline library when possible, but a missing or broken offline toolchain falls
back to the compiler-generated sibling MSL without degrading the GPU engine.
`METAFLIP_FORCE_RUNTIME_MSL=1` forces that path for diagnostics.

The production mixed fleet is still Metal-only. For an NVIDIA cloud campaign,
[`cloud/cuda/`](cloud/cuda/README.md) contains a deliberately narrow 7x7
relay: it emits CUDA from the canonical Tungsten cooperative kernel, rotates
several exact rank-247 doors, exhaustively host-gates every device claim, and
writes atomic status/checkpoint files. It is a fail-closed campaign harness,
not a second implementation of the full adaptive fleet.

## Files and state

The package keeps its public API, executable, immutable runtime, mutable state,
and curated results separate:

- `bin/metaflip.w` is the command-line entry source. `tungsten build` compiles
  it to `bin/metaflip`; `bit build` installs it to `build/bin/metaflip`.
- `lib/metaflip.w` is the side-effect-free public library entry. Importing it
  exposes scheme, verifier, rectangular, composition, and path APIs without
  starting a fleet.
- `lib/metaflip/` is the single immutable runtime namespace. Its top-level
  files are the public subsystems; `fleet/`, `strategies/`, `kernels/`,
  `rect/`, and `seeds/` contain implementation modules and operational data.
- `lib/metaflip/seeds/gf2/` contains only exact schemes needed to start or
  diversify supported campaigns. These are inputs, not an accumulating
  results archive.
- `lib/metaflip/manifests/seeds.tsv` links every bundled seed by SHA-256 to its
  attributed path in the curated results corpus. `lib/metaflip/SHA256SUMS`
  protects the complete immutable runtime subtree.
- `~/.tungsten/metaflip/` is the default live store for checkpoints, run
  status, near-rank banks, and newly discovered candidates. Override it with
  `METAFLIP_HOME` or `--state-dir PATH`.
- Every square-fleet status heartbeat includes bounded `best_source_kind`,
  `best_source`, `best_strategy`, worker/slot, round, parent identity/quality,
  basin distance, and candidate identity/quality fields. After an exact best
  checkpoint is committed, Metaflip also atomically replaces
  `<best>.provenance` with the same one-line adoption event. Match its
  `best_id`, rank, and density to the certificate when harvesting after an
  abrupt stop; a missing or stale telemetry sidecar never invalidates the
  independently exact certificate.
- `tungsten-metaflip-results` is the separate curated public repository for
  verified certificates, known bests, attribution, and record provenance.
  Promote a live result there only after independent verification.
- [tungsten-lang/metaflip-archives](https://github.com/tungsten-lang/metaflip-archives)
  stores bulk research evidence as release assets. Its Git history contains
  only indexes, checksums and upload receipts, not large tarballs. Archives
  include bounded and negative studies; hosting a snapshot is not record
  promotion. Repository access may require authentication.

Temporary worker binaries, Metal sources and libraries, rejects, and scratch
data may use the system temporary directory. Runtime compiler output is
explicitly directed there, so an installed bit never accumulates generated
CUDA, LLVM, Metal, AIR, or metallib files. These are caches, not certificates.

## Correctness and publication

Every admitted candidate is reconstructed against the complete target tensor;
GPU hits are host-gated before promotion. That gate protects the live search,
but a claimed record should still be replayed independently and published with
its coefficient domain, shape, rank, density, discoverer, provenance, and
digest.

The generalized rectangular k-XOR objectives, endpoint-to-word compilers,
one-spectator repair, computed rank-one/rank-two/rank-three completion ladder,
four-line catalyst, and double-annihilation macro under
`lib/metaflip/strategies/` are offline research tools. They can verify a
prescribed local replacement and compile a replayable exact setup/flip/cleanup
word, but they are not production fleet lanes unless matched frontier
experiments show useful candidates.

### Offline composition tools and local studies

The dated benchmark audit directories referenced below are historical generated
evidence. Wholly untracked dated folders are preserved in the `checkout-audits`
release assets of [metaflip-archives](https://github.com/tungsten-lang/metaflip-archives).
Use its `archives.json` folder inventory to find the matching snapshot, verify
its checksum, and extract it into a fresh directory when those inputs are
needed. Curated records, proof fixtures and tracked sources remain here.
These snapshots are byte-preserved evidence bundles,
not part of the source-only package. Reusable tools and tests are versioned;
generated tensors and imported leaves remain separate pending provenance and
redistribution review. A missing local audit directory is not a test dependency.

`tools/bud_products.rb` is an offline, arbitrary-width GF(2) composition
experiment. It searches disjoint equal-factor groups (buds), composes them
with exact local leaf witnesses, and saves self-contained replay recipes.
Its `--leaders-only` control measures what is lost by discarding alternate
and higher-rank parents. It never mutates the live fleet archive or labels an
output a world record. See [the bounded scan and replay instructions](tools/BUD-PRODUCTS-2026-09-06.md).
These wide products are not implicitly admitted to the u64 flip kernels.

`tools/bud_parent_walk.w` and `tools/bench_bud_parents.rb` add a bounded native
parent-walk experiment with certificate-backed composition scoring and
matched ordinary/greedy/annealing controls. The measured strategy tradeoffs
and independently verified product witnesses are in
[the parent-walk report](tools/BUD-PARENT-WALKS-2026-09-06.md).
This remains offline: greedy acceptance did not beat ordinary wandering in
the matched study, and no new production strategy is enabled by it.
`bench_bud_parents.rb`, `bud_products.rb`, and `bud_packings.rb` accept
`--native-spool /path/to/status.txt.refinement` to reuse a native run's
verified leaf banks. This closes the cost mismatch where a packaged-only
offline library missed the native rank-15/rank-26 small leaves. Each bank and
member crosses hash, shape, canonical-format and full tensor checks; the
selected witnesses are snapshotted into the study's self-contained recipes.
The option does not mutate or launch the fleet. See the
[native-bank search audit](tools/NATIVE-BANK-SEARCH-2026-09-09.md).
The packer accepts the option in direct-parent and `--from-report` modes,
so exact mixed-group refinement can preserve a native-bank baseline's leaf
prices. The [projection/packing follow-up](tools/PROJECTION-PACKING-2026-09-09.md)
records three expanded local improvements but no new reference crossing;
its unsuccessful projection-selector change was not enabled.
The native parent walker also accepts optional
[mixed-packing observers](tools/BUD-MIXED-OBSERVERS-2026-09-09.md), scoring up to
eight mixed-axis contexts from the same unmodified walk. Canonical private
copies reproduce the automatic composer's exact/fallback prices. Two matched
studies retained six distinct control-relative improved target shapes, with
ten full output replays, but none beat the retained archive. This remains
opt-in offline research, not an additional default CPU/GPU lane or a flip
throughput improvement.
Named `mixed-observers groups N BUDGET` and `mixed-observers grids N BUDGET`
now retain up to eight native group/grid objectives without changing the
walk. A seven-parent matched study, including 3x3/4x4/5x5 and scale-one
composition contexts, verified twelve control-relative target gains from
one new rank-23 3x3 representation, but no new retained bound. All 329
distinct outputs also passed exact matrix-cleanup replay without a reduction.
These numeric observer profiles can include verified scale-one leaves.
The automatic composer now also schedules the 27 exactly-one-unit contexts
using literal unit leaves alongside its unchanged bank; nine single-axis-only
contexts in the offline 63-context audit remain outside automatic scheduling.
An optional [packing-driven primary objective](tools/PACKING-PRIMARY-WALKS-2026-09-09.md)
now lets this research walker use the native mixed-pair, size-2/3/4 group,
or combined group/2x2-grid price for chunk acceptance and winner selection.
Unlike observers, it can
steer greedy/annealing trajectories; ordinary walk endpoints remain unchanged.
Two bounded matched studies plus broader leaf/grid repricing retained 280
distinct parents. Five target minima beat both matched controls, but none
beat the retained archive. This is not enabled in the live fleet or exposed
by `bench_bud_parents.rb`; numeric tables must be bound to verified leaf
witnesses before any product is admitted.
A matched grid-primary follow-up tested 2.416 billion attempts under two
exploration envelopes, retaining 881 distinct parents and repricing 23,787
parent/context recipes. No retained bound improved. Matching the acceptance
policy exposed losses from greedy grid steering, so it remains opt-in;
automatic grid composition is still enabled independently of search steering.
The [two-grid follow-up](tools/TWO-GRID-PARENT-2026-09-09.md) found a new
rank-104 4x5x7 representation in the ordinary control arm. Full grid packing
and checked block composition yield five verified local improvements,
including 8x10x14/724 and 8x14x26/1805 below the refreshed screened references.
These are GF(2) candidates, not confirmed world records. Their two disjoint
2x2 grids are now supported by the native automatic composer; the
held-grid search policy itself did not produce these wins.
Optional [read-only context observers](tools/BUD-CONTEXT-OBSERVERS-2026-09-08.md)
retain up to eight additional price objectives along one ordinary walk. The
same-path study reproduced both rank and context winners with half the
duplicated attempts, and recomposition found three new reference-crossing
GF(2) candidates (not confirmed world records). Observers are off by default,
verify complete tensors, and do not steer or add a live fleet lane.
[Batched scoring](tools/BUD-BATCHED-OBSERVERS-2026-09-08.md) now shares axis
grouping across observers. Matched eight-observer runs cut native time by
18–33% on the tested 4×4×5/5×5×5 parents with identical outputs; this is not
a default-fleet speedup. Its follow-up search verified five local product
improvements but found no new reference crossings.
[Primary-plus-observer scoring](tools/BUD-UNIFIED-OBJECTIVES-2026-09-08.md)
now shares the remaining primary grouping pass too. Matched runs retain exact
outputs and cut observer-enabled native time by 4–8% on the tested larger
parents. A bounded projection/continuation follow-up independently verified
5x32x32 at rank 3430 (previous local 3460; pinned reference 3200), not a record.
[Structured integer-source import](tools/BUD-STRUCTURED-IMPORT-2026-09-08.md)
now handles rectangular orientations and non-ternary coefficients with full
integer and GF(2) checks. Importing 28 additional literal literature parents
gave 131 lower local composition prices; five expanded products pass independent
replay, but none newly crosses the pinned reference bounds. The importer is
offline and does not automatically admit seeds or clear redistribution rights.
[Structured-parent continuation](tools/BUD-STRUCTURED-CONTINUATION-2026-09-08.md)
then verified a GF(2) 21x24x30 upper bound of 8064, below the refreshed bounded
reference screen of 8067. Two additional shared-U pairs in a rank-150 5x6x7
parent supply the saving; its primitive rank is unchanged. This remains a
reference-crossing candidate, not a confirmed world record. A reusable
`verify_observer_walk.py` now checks the saved observer tensors and scores.
[Projection continuation and admission](tools/BUD-PROJECTION-ADMISSION-2026-09-08.md)
adds four checked local product improvements, but no reference crossings.
Rank-only controls now share that replay format, and
`extend_composition_parents.py --observer-walk` admits their verified full
states, including endpoints, without one-off audit/admission scripts.
[Explicit lineage and composition observers](tools/BUD-OBSERVER-LINEAGE-2026-09-08.md)
retain every cell/trial/role occurrence and correct a five-seed cohort-labeling
error without discarding valid tensors. The follow-up checks three more local
products, including 16x18x30 at 4833 (a pinned-reference tie, not a new record).
The bounded cohort now totals 258 lower-local-price shapes, 21 expanded and
237 recipe-only; the scoped reference-crossing shortlist remains 42.
The optional [fixed elementary-group objective](tools/BUD-FIXED-GROUP-WALKS-2026-09-07.md)
keeps a verified leaf cover while walking the remaining terms, including
parents above rank 64; its first matched study found no further rank gain.

`tools/bud_packings.rb` adds a bounded exact disjoint-bud packing check with
explicit incomplete-result flags and baseline recipe replay. The
[packing and neighborhood follow-up](tools/BUD-PACKING-FOLLOWUP-2026-09-06.md)
documents the two further local product improvements and the negative
rank-debt/density-slack sweeps. These results do not establish world records.
The [September 7 follow-up](../../benchmarks/matmul/metaflip/near_packing_followup_audit_2026_09_07/README.md)
retains 56 more independently verified local bounds and matched dense-component
packing measurements. `tools/bud_component_dp.w` is an optional offline exact
subset oracle; it is not enabled in the live flip fleet or shared packer.

`tools/scan_parent_covers.rb` scans frozen retained families with explicit
`--all` or heuristic `--sample` selection, bounded time and independently
checked coverage. The [5x5x6/5x5x7 follow-up](tools/BUD-PARENT-COVER-SCAN-2026-09-08.md)
finds 24 lower local composition prices and independently expands six products,
including propagation to 26x31x31. It does not claim new world records or alter
the live fleet.

The [projected-parent follow-up](../../benchmarks/matmul/metaflip/projected_parent_composition_audit_2026_09_07/README.md)
retains 453 exact near-best small representations rather than only rank leaders.
Their recomposition gives 268 independently checked local bounds, ten below the
dated public-reference closure, including 14×16×16 at rank 2,062. These remain
GF(2) candidate records, not confirmed novelty or matrix-kernel speedups. The
offline projection scanner and independent replay do not change the live fleet.
The [all-image control study](../../benchmarks/matmul/metaflip/projection_variant_followup_audit_2026_09_07/README.md)
kept another 3,857 exact images and found six further local bounds, but no new
reference crossing or measured benefit from nonminimum images. Its pricing
template cache reduced offline construction CPU by 2.30× on the matched
small-target workload while preserving every parent and exact witness choice.
The [linear-projection follow-up](../../benchmarks/matmul/metaflip/linear_projection_followup_audit_2026_09_07/README.md)
adds independently checked one-sided and paired XOR restrictions. Its three
bounded scans retained 3,849 new representations but found no further local
bound. The offline planner now reuses an unchanged closed table only after
checking explicit coverage of every appended ordinary pricing expression;
all tensor identities remain available, and new expressions still run the
complete planner. `--no-reuse-priced-expressions` selects the matched control.
The [joint-projection follow-up](tools/JOINT-PROJECTIONS-2026-09-08.md)
adds simultaneous two-coordinate restrictions without an intermediate rank
gate and optional exact pair cleanup before final retention. Its independent
checker also verifies sources of negative scans. The bounded projection arm
found no lower primitive rank; an ordinary-walk control yielded three further
verified local composition bounds, with no new public-reference crossing.
These tools remain offline and do not enable an additional fleet lane.

[Balanced dual refinement](tools/BALANCED-DUAL-PROJECTIONS-2026-09-08.md)
extends the offline runner to sparse paired kernels on large shared dimensions.
Lazy XOR tables avoid exponential allocation, and coordinate/delta reuse cut
CPU time by 16.8% in a matched 1,690-view replay with identical retained tensors.
The all-anchor follow-up verifies 20x23x29 at 7,430 and a 21x23x29 block at
8,097, with six lower local composition prices and no new reference crossing.
This is an offline workload measurement, not a live-fleet speedup.
The same runner can now refine an audited paired map with
`--dual-edit-radius 1`, `2`, or `3`, with exact preflight limits and independent
map/cleanup replay. The initial neighborhoods tied the existing ranks; varied
cleanup orders retained a second exact 7,430-term representation for downstream
search, not a new rank record.
Replaying downward projections of those parents then verified 20x23x28=6,970
(previously 6,982), and its 21x23x28 block at 7,614. Seventeen local prices
improved; the cumulative cohort is 389 shapes (55 expanded, 334 recipe-only),
with no additional reference crossing or confirmed world record.
For targeted coordinate follow-ups, `projection_composition_scan.py` accepts
`--target SHAPE --targets-only` to skip the otherwise additive default
neighborhood. A [focused recursive projection](tools/PROJECTION-SHORTLIST-2026-09-08.md#focused-target-only-follow-ups)
and second-axis paired refinement independently verified 20x23x27=6,920,
improving the previous 6,931 bound, and expanded its 22x23x27 block at 7,878
(already dominated by a 7,735 padding bound). The next step independently
verified **20x23x26=6,834**, improving the padding-corrected 6,852 bound by 18,
and completed the earlier 23x23x27=8,304 recipe. The cumulative raw-price
audit cohort is 392 shapes (58 expanded, 334 recipe-only); after removing
81 shapes dominated by current padding bounds, 311 remain (54 expanded,
257 recipe-only). There is no new reference crossing or confirmed world
record. These projection searches remain offline; their pair and matrix
cleanup primitives are now also used by live candidate admission. New replay evidence
is compressed and deduplicated outside the checkout.

For offline replay, `tools/compress_checked_products.rb SOURCE OUTPUT`
accepts audited composition, flat projection, and observer-walk reports. It
exactly factors the matrix formed by terms sharing one factor, matching the
native matrix-cleanup primitive. The independent
`verify_product_compression.py OUTPUT --workers 1` replays the factorization
and complete tensors, including source-rank checks. Walk intake includes every
rank winner, context winner, and endpoint. It checks all snapshot references
before deduplicating by exact shape and tensor hash; stale duplicate metadata
cannot disappear in that step. It does not run on every live flip.
A bounded basis-refactoring
follow-up then reached **20x23x26=6,742** and **20x23x27=6,844**, and their
recomposition verifies **23x23x27=8,228**. See the
[shared-factor follow-up](tools/PROJECTION-SHORTLIST-2026-09-08.md#shared-factor-matrices-and-neutral-bases)
for padding-corrected counts and replay evidence. These stronger operations
remain offline; no live-fleet throughput or world-record claim is made.

The offline `checked_price_library.rb` now backtracks over price-compatible
block/Kronecker alternatives when a component has no witness. Corrupt sources
remain fatal. This recovered 16 previously failing constructions; subsequent
wide matrix cleanup verified **19x27x28=8,129**, versus retained 8,169, still
above the saved public comparison 7,983. See the
[native-feedback and backtracking audit](tools/NATIVE-FEEDBACK-BACKTRACKING-2026-09-10.md).

The coordinate projection scanner also offers `--pair-order 0,1,2
--matrix-cleanup`: score **every** view after matrix factorization, rather
than factor only the pair-ranked winner. It is opt-in, requires Ruby, and
keeps one serial Ruby worker per configured projection worker. With
`--workers 1` only one candidate is processed at a time. Python independently
replays the selected projection, pair reduction, matrix factorization and
complete tensor. The matched 81-view test selected rank 6,755 rather than
6,761; bounded basis refinement then verified **20x23x26=6,740**. Repricing
also lowered the 23x23x26 and 23x26x26 recipes to 8,074 and 9,018. Neither
recipe has been expanded at its new price. The cumulative counts remain
396 raw-price shapes (57 expanded, 339 recipe-only), or 314 after padding
(54 expanded, 260 recipe-only). No new reference crossing or world record.
See the [matrix-scored projection audit](tools/PROJECTION-SHORTLIST-2026-09-08.md#matrix-scored-coordinate-projections).

A 348-view neighbor follow-up plus bounded basis refinement independently
verified **19x23x26=6,623**, **19x23x27=6,721**, and **20x22x27=6,701**.
The cumulative raw-price cohort is now 399 shapes (60 expanded, 339
recipe-only); 316 survive padding (56 expanded, 260 recipe-only). No new
reference crossing or main-square improvement. The independent matrix
checker now constructs only nonzero coordinate rows, retaining the separate
rank tests, row solve and full reconstruction. A matched two-configuration
replay was about 4.8x faster; the complete 39-tensor audit reproduced its
previous result exactly. This speeds offline verification, not live flips.
See the [neighbor and replay audit](tools/PROJECTION-SHORTLIST-2026-09-08.md#neighbor-projections-and-sparse-row-replay).

A [compact-parent follow-up](tools/COMPACT-PARENT-PROJECTIONS-2026-09-08.md)
finds a rank-85 4x4x7 representation with 38 shared-factor pairs. Its primitive
rank is unchanged, but its grouping gives verified larger bounds including
7x12x12=651 and 28x32x32=14,122. Coordinate/matrix cleanup also verifies
15x15x15=2,030 and 15x15x16=2,081. The cumulative cohort is now 787 raw-price
shapes, or 630 after padding (115 expanded, 515 recipe-only); all 68 cohort
reference crossings are expanded. These remain source-scoped candidates,
not confirmed world records. This was an offline campaign; native matrix
cleanup and bounded basis/projection scheduling are now integrated as described
above. Replay evidence is compressed outside the checkout.

The [composition/restriction follow-up](tools/COMPOSED-PROJECTION-CANDIDATES-2026-09-11.md)
fully checks GF(2) candidates 8x11x11/r640, 8x11x12/r673 and 8x11x16/r895,
plus two larger Strassen products. All five beat the checked reference
snapshots; global novelty and redistribution clearance remain unclaimed.
This bounded offline study preserves equal-rank variants and does not change
runtime scheduling or canonical seeds.

`tools/wide_group_plans.py` now adapts those multiword parents to the native
mixed-group/grid planner using exact factor labels and bounded equality
components. It returns checked plans, not admitted tensors. The
[wide-group follow-up](tools/WIDE-GROUP-ADAPTER-2026-09-11.md) fully verifies
48 compositions and 135 selected restrictions, with no new best rank.
Equal-cost grouping in the tested leaf bank reproduces plain products;
different leaf presentations or embeddings are the next useful experiment.

The subsequent [per-slot leaf campaign](tools/PER-SLOT-LEAF-CANDIDATES-2026-09-11.md)
uses each outer term's actual block extents to choose its checked leaf. It
verifies **7x11x12/r613, 8x11x11/r631, 8x11x12/r669 and 8x11x16/r891**,
then expands four larger reference-crossing constructions. Full replay and
corruption checks pass; these remain source-scoped GF(2) candidates, not
confirmed world records. The existing offline tools perform this campaign;
it is not another automatic runtime lane or a main-square improvement.

`tools/composition_closure.rb` checks candidates against a verified recursive
block/Kronecker library and propagates useful candidates to other shapes.
It exports both comparison and candidate tensors for independent replay.
The [closure and catalog audit](tools/COMPOSITION-CLOSURE-2026-09-06.md) separates
31 further local improvements from already-known constructions and the
remaining novelty-audit shortlist. `bud_products.rb --recursive-products`
enables the same optional leaf-pricing family; the default is unchanged.

Bundled seed files can have licenses or attribution requirements different
from the engine. Read [THIRD_PARTY.md](THIRD_PARTY.md) before redistributing a
package archive or adding a new imported seed.

## License

Except for separately identified third-party data, this bit is licensed under
`MIT OR Apache-2.0 WITH LLVM-exception`. See [LICENSE](LICENSE).
