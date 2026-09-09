# Automatic scale-one mixed composition

The cold composer now considers 54 contexts per distinct verified
parent/bank/packing-mode combination: the existing 27 scales in `{2,3,4}^3`,
plus 27 with exactly one coordinate equal to one. This is a constructive
coverage extension, not a new tensor-rank or world-record claim.

The fixed-axis composer already reproduced 4x7x4/r85 at scale 3x1x3 as
12x7x12/r651 (a permutation of 7x12x12). That regression is not credited
again. The new mixed domain additionally covers unequal scales such as
2x1x3 and allows the same bounded pair/group/grid packing on them.

## Witnesses and replay

`MFM_BANK1` is unchanged: 22 canonical tensors with their existing immutable
hashes. Any required leaf with a unit dimension is generated from the literal
matrix-product triples `(E_ij,E_jk,E_ik)`. The masks themselves, not just their
count, are substituted into the parent. Optional group/grid leaves still
require an available witness. A unit leaf with a factor width above 63 is
disabled, preventing signed-mask overflow; for example 1x4x16 and 1x8x8 are
not silently included. A context with one unavailable optional leaf may
still use its other witnesses.

Every expanded multiword tensor crosses the existing complete identity
check before archive, best or completion writes. State/probe exhaustion
retains the earlier constructive plan and never establishes optimality.

| Packing | Existing domain | Exactly-one-unit domain |
| --- | --- | --- |
| Pairs | MFM1 / MFMD1 | MFM4 / MFMD4 |
| Groups | MFM2 / MFMD2 | MFM5 / MFMD5 |
| Groups and grids | MFM3 / MFMD3 | MFM6 / MFMD6 |

Each parent ticket retains 27 cursor positions. New-domain context `i`
fixes coordinate `i/9` to one; the other two coordinates are
`2+(i%9)/3` and `2+i%3`, in coordinate order. Old mapping, task bytes,
bank hashes, schedules and journals are not migrated or overwritten.
Re-offering a previously seen parent appends only its missing versioned
reference. The two offers are separately durable and idempotent, including
a restart between them.

## Bounds and controls

There is still one low-priority cold worker, at most 27 admitted contexts
per slice, at most four exact expansions per batch, and the existing shared
pending cap/backpressure behavior. More deferred references do not reserve
an unbounded batch. Stop, resume and visible deferred counts use the same
queue. No CPU/GPU flip loop, worker count or default flip objective changed.

`METAFLIP_COMPOSITION_SCALE_ONE=0` suppresses new unit-domain intake only;
committed work still drains. Existing group/grid opt-outs select the
corresponding algorithm in both domains. Disabling all mixed intake still
leaves existing tickets replayable.

Direct native composition accepts scales 1..4. Automatic scheduling does
**not yet** include the nine nonidentity contexts with two unit coordinates,
nor identity scale 1x1x1. Single-axis expansions can have useful grid
constructions; this omission is a bounded implementation scope, not a
dominance theorem. No arbitrary larger leaf search or dependency rescan
was added.

## Focused checks

Build the `mixed_composition_test.w`, `mixed_group_composition_test.w` and
`refinement_backpressure_test.w` fixtures with release/native compilation.
Run `scale_one_composition_test.py GROUP_BINARY PAIR_BINARY QUEUE_BINARY`;
the optional `--parent EXTERNAL_RANK85_4x7x4` adds the 651/1132 regressions
without redistributing an imported tensor. `--root NEW_OUTSIDE_DIRECTORY`
retains queue evidence; otherwise the test uses a temporary directory.

The check independently substitutes all 36 added nonidentity direct
contexts for all three packing modes, tests bounded fallback and positive
mask boundaries, and verifies complete tensor identities. It separately
exercises six-version coexistence, old-ticket immutability, two-offer and
task/cursor recovery, algorithm/domain tampering, disabled-intake draining,
shared occupancy, bounded admission and the deferred-only coordinator.

The original pair/group/grid parity, legacy-domain queue, backpressure and
public-binary refinement checks remain the regression gates. These are
correctness and integration tests, not isolated throughput measurements or
a fresh best-known-reference audit.

The release/native suite passes **119 direct full substitution/tensor
replays**, including the retained rank-85 parent at 651 and 1,132. The
non-release group fixture passes 117 direct replays and the same queue
suite without the optional external parent. All 270 mixed completion
records in the retained version/recovery/coordinator cases independently
replay. The original suites pass: pairs 369 plans / 194 full replays;
groups 259 plans / 45 replays; grids 197 plans / 40 replays, including the
already retained 724/1,548/1,542 constructions. Legacy-domain queue and
source-backpressure tests pass unchanged in scope.

The public executable was rebuilt with the Bitfile's release/native
defaults. Its bounded CPU-only 5x5 and 2x5x6 refinement tests pass, including
seed feedback, resume, disable and shutdown. No GPU test or isolated speed
claim is made; every test-owned search/worker stopped. These integration
checks do not add to the research rollup of 2,119 distinct searched parents
and 69,057 checked parent/context pairs, or establish any new retained bound.

Evidence remains outside the checkout. The durable local archive is
`/Users/erik/.local/share/tungsten-metaflip/evidence/2026-09-09-scale-one-composition.tar.gz`
(478,014 bytes; SHA-256
`80be562b98c60144c3d40cce8f8f486f5ed7d92f866ca0958215a7c1259cb676`).
Fresh extraction checked 957 manifest hashes, 270 mixed and 18 fixed-axis
completion records, 171 narrow objects and three retained direct outputs.
The manifest records the scoped source, independent Python import closure,
native binary hashes and test provenance. Imported witnesses remain local;
no redistribution or worldwide-novelty claim follows.
