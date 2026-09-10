# Automatic native wide refinement

Ordinary `bin/metaflip` now schedules bounded wide basis/projection work after
verified composition cleanup. This closes another offline integration gap;
it is not a new tensor-rank result. Narrow candidate refinement, search-seed
feedback and incremental composition were already native. The new lane also
handles composed witnesses whose masks exceed the live walker's u64 limit.

## Candidate flow

1. Verify the composition and preserve its original recipe/object.
2. Run bounded strict matrix cleanup and read its admitted result identity.
3. Offer that identity's basis family and coordinate-deletion family.
4. For every admitted distinct basis endpoint, offer its deletion family too.
5. Fully verify each result before indexing by shape and full tensor identity.

Rank ties are retained. Candidate identity includes all terms, not just shape,
rank, pair count or a hull descriptor. A stopped, corrupt or verification-limited
proposal is not reported as an admitted improvement. Replayed tasks recompute
the transformation and full tensor gate; checksummed result records are not
accepted as mathematical authority.

The 18 basis contexts comprise six single-axis proposals and twelve two-cycle
proposals: all six axis orders, each with ascending/descending column selection.
Each context ends with strict matrix cleanup. Coordinate deletion contracts the
correct U/V/W grids and removes empty/duplicate terms before cleanup. All
operators are native Tungsten. Python remains an independent testing oracle.

This is deliberately a finite generation. Projections do not recursively start
new basis/projection families or compose their wide outputs again. Wide outputs
are verified archives, not silently converted into u64 walker seeds. Automatic
wide-to-composition feedback remains a separate integration step.

## Scheduling, persistence and limits

The existing single low-priority native child owns all writes. A transform is
one scheduler turn, and its at-most-two successors append behind existing work.
It normally receives one in three composition turns. At 256 pending transform
contexts, the scheduler prioritizes that lane before making new composition
roots. Pending continuations can grow temporarily above 256; this is a
high-water throttle, not a hard queue length or disk-byte quota.

A context uses at most six basis passes and one cleanup, each capped at 20M
algebra units. Full verification separately has a 20M-XOR limit. These bounds
do not promise a wall-clock deadline. All masks/ranks obey the existing
1,024-bit-factor / 16,384-term limits. Stop is checked between passes and before
admission/acknowledgement. There is no unlimited retry on a work limit.

Task/result journals use 64-record checksummed pages. Source/context indexes
are also paged: there is no individual global task/index file for each
projection. The append/index/counter order recovers a lost tail acknowledgement;
idempotent source/context binding recovers a lost consumed cursor even if
another producer appended meanwhile. Old primary tickets and formats remain
unchanged. There is no concurrent-writer protocol; the single-child ownership
is an explicit invariant.

`wide_transform_submitted/completed/pending/failures/status/delta` appears in
the status file; the TUI includes transform progress and failures. Pending
counts only materialized contexts, not all future continuations. Status 1 is a
completed context, 2 algebra-limited, 3 verification-limited (0 initially idle).
The latest delta is an admitted before/after term difference, **not** a record
count; a projection changes the shape. `METAFLIP_WIDE_TRANSFORMS=0` pauses this
lane and disables new intake without discarding old work. An error remains
visible and its task remains pending. Existing primary-lane errors can still
pause the shared coordinator; this change does not add failure isolation.

## Focused regression gates

- Synthetic automatic queue: 169 contexts (36 basis, 133 projections), including
  14 changed rank ties and six independently expanded tensor identities.
- Stop/intake, duplicate contexts, out-of-order contexts, interrupted append,
  interrupted consumption, concurrent-in-time producer append, source corruption,
  and checksummed forged-result rejection.
- Small paged-file count, byte-identical replay, and preserved rank-tied objects.
- Public four-context batches actually complete four contexts. This catches the
  initial wide-only loop bug that launched a child for each individual task.
- Public one-CPU/no-GPU fleet startup, automatic transforms, seed reuse, stopping,
  restarting and refinement-disabled controls.
- Existing packed-composition and strict-wide-cleanup parity/replay checks.
  Legacy fixed/mixed scheduling controls explicitly disable the new lane.

Example commands from the repository root:

```
bin/tungsten compile bits/tungsten-metaflip/spec/wide_transform_queue_test.w --out /tmp/wide-transform-test --release --native
python3 -B bits/tungsten-metaflip/spec/wide_transform_queue_test.py /tmp/wide-transform-test /tmp/new-wide-transform-check bits/tungsten-metaflip/bin/metaflip
python3 -B bits/tungsten-metaflip/spec/refinement_fleet_test.py bits/tungsten-metaflip/bin/metaflip /tmp/new-wide-fleet-check
```

Test output directories must be new. The runtime build uses the local cached
compiler/runtime with release/native defaults; it is not a clean compiler
bootstrap. No full local `rake` suite is run.

## Retained-shape run

A one-worker, no-GPU, 180-second public-binary run starts from the sixteen
retained wide shapes in the prior study plus the old 19x27x28/r8129 regression
input. Its comparison table already includes r8109, so rediscovering that
witness cannot be counted as another gain.

The bounded run completes 5,215 contexts and stops with 122 materialized
contexts pending. It does not exhaust the projection family. Its numerical
screen reports no additional retained bound. The full independent corpus replay
is still in progress at this integration commit; do not treat that screen as
a completed independent audit. Its checkpoint is
`/private/tmp/metaflip-wide-auto-study-20260910/report.json`; a successful full
replay will add `audit.json`. The run used the initial
batch loop; the subsequent batching-only control checks byte-identical tasks
and results across the fixed loop on a matched 64-context workload.

That completed matched control reduces launches from 64 to 16. One observed
run takes 7.52s versus 6.40s while another audit is running; this is not a
fleet-throughput claim. All 64 result recipes agree byte-for-byte, and the
independent replay checks ten basis contexts, 54 projections and 65 complete
tensors. The separate final public-fleet tests independently expand 170
distinct tensors across 51 shapes; none beats the current retained table.
Reports are in `/private/tmp/metaflip-wide-batching-study-20260910/report.json`
and `/private/tmp/metaflip-wide-transform-public-final-20260910/bound-audit.json`.

No fresh public-record audit, new record claim, canonical seed promotion or GPU
campaign is included. Bulk tensor objects and binaries remain outside the
repository; only runtime code, focused specs and this report are added here.
The six unrelated dirty compiler/runtime/spec files are unchanged; their
combined diff SHA-256 is
`2f741028f621d98408d438dd598a8738b499710070aae691675a893a9bc8cf42`.
