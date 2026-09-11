# Seeded matrix-basis diversification

This adds a deterministic native proposal operator and independently tests a
broader basis family. The bounded search finds **no new retained rank**. It
does not establish a world record or justify adding more automatic queue work.
The operator therefore remains an explicit experimental library API; ordinary
MetaFlip keeps its existing automatic cleanup/basis/projection schedule.

## Operator and gates

`ffwm_refactor_seeded` groups terms by a shared factor and exactly refactors
each group's remaining matrix, choosing columns in a seeded permutation.
It salts a 32-bit seed with every limb of the fixed factor and uses a specified
Fisher-Yates permutation over the full padded width. This can reach bases that
neither ascending nor descending column order reaches: a dependent three-column
fixture produces three distinct valid bases. It is not an exhaustive search of
all matrix factorizations, nor a cryptographic random generator.

The API accepts factors through 1,024 bits and at most 16,384 terms, matching
the existing wide format. Callers allocate `ffwm_seeded_scratch_words`, which
adds one 32-times-stride column-order array to the old scratch requirement.
Permutation work is charged before mutation. A budget-limited group is left
intact; the caller must inspect status and fully check outputs before admission.
Invalid seed, axis, budget or slab arguments fail without changing input/stats.

Legacy ascending/descending refactors and strict cleanup retain their exact
output bytes and logical work counters. No throughput claim follows from that:
the extra mode branch has not received a matched CPU performance benchmark.
There is no new public `bin/metaflip` command-line flag or default seeded lane.

The independent oracle relabels matrix coordinates, runs the existing integer
row-equation solver, and inverts the relabelling. It does not reproduce the
native incremental column-elimination implementation. Focused gates pass:

- 844 seeded/budget cases, including 356 deliberately limited runs;
- 60 complete matrix-multiplication tensor checks;
- 112 byte-and-counter-identical comparisons against the pre-change binary;
- malformed/nonmutating gates across limb boundaries through 1,024 bits;
- the existing 864 legacy-basis cases and 219 projection cases;
- the native 169-context queue, public four-context batching and public fleet
  startup/seed-feedback/stop/restart/disabled controls.

From the repository root, with a fresh report path:

```
bin/tungsten compile bits/tungsten-metaflip/spec/wide_matrix_cleanup_test.w --out /tmp/seeded-basis-test --release --native
python3 -B bits/tungsten-metaflip/spec/wide_seeded_basis_test.py /tmp/seeded-basis-test --report /tmp/seeded-basis-report.json
```

`--legacy OLD_TEST_BINARY` adds the byte/counter comparison. The test binary's
`--basis-seeded INPUT OUTPUT BUDGET AXIS SEED` interface is for controlled
experiments, not a public fleet option.

## Bounded useful-shape search

The run starts from the same 166 pinned tensors across 51 canonical shapes as
the [mixed-direction audit](MIXED-DIRECTION-SEARCH-2026-09-10.md), including
the main square families. It proposes seeded axis permutations for at most two
cycles, followed by strict cleanup. Each pass and complete verification has
a separate 20M work limit. Full tensor identity keys operations and endpoints.

One low-priority CPU worker runs for 180 seconds with no GPU. It completes
1,046 contexts, six or seven per input, from a planned sixteen per input:
this is a bounded sample, **not exhaustion even of that finite family**.
There are 5,657 distinct native operations (5,072 seeded passes and 585
cleanups), 2,329 intermediate objects and 696 fully native-verified endpoints.
No step or endpoint is work-limited. Independent replay reconstructs every
operation/context and metadata row and expands 186 distinct input/best tensors.
No retained primitive bound improves, including the main cubes.

There are 530 endpoints new relative to this run's inputs. Of these, 64 already
occur in the preceding mixed-direction study, so this adds **466 distinct
representations**. Across those two studies the deduplicated total is 1,077
non-input representations, or 1,243 including the 166 shared inputs. These are
representations, not improved shapes or world records; other historical
campaigns are outside this particular rollup.

The seeded report SHA-256 is
`d71fbc58b831876be60c84ad58cc0531ba73e0b089c8fde937b496489cd06968`.
The saved 5,984-shape comparison includes earlier gains and all input ranks,
so rediscovery cannot count as another improvement. No public-record refresh
is needed to report the negative result; the saved table is not claimed current.

## Composition and projection follow-up

419 new small-parent representations receive all 63 scale triples in
`{1,2,3,4}^3` except `(1,1,1)`: **26,397 native composition-price contexts**.
Returned disjoint group/grid plans and costs are independently checked. They
cover 684 target shapes; ten outside the saved table are explicitly unknown.
None crosses a known retained bound. Formula prices do not certify tensor rank
or optimality and do not rule out post-expansion cancellation.

A shape-diverse selection then fully materializes 96 constructions from
24 parent-shape families, covering 92 targets. Native leaf substitution agrees
with independent full expansion. Every tensor identity and subsequent exact
matrix cleanup passes; none is limited, reduces rank or improves the table.
Other pricing contexts are not claimed fully materialized or ruled out.

For projections, select up to two minimum-rank seeded endpoints per shape:
one by shared-pair count, another by term-set distance. These are ordering
heuristics, **not dominance rules**. Round-robin deletion of coordinates from
78 parents completes 1,341 of 2,210 planned contexts in 120 seconds, across
86 target shapes. Every deletion agrees with independent row-block contraction,
every cleanup agrees with the matrix oracle, and every resulting full tensor
passes native and independent verification. No rank beats the saved bound.
The remaining projections are untested, not rejected.

## Integration boundary and next useful work

The [automatic pipeline](AUTOMATIC-WIDE-TRANSFORMS-2026-09-10.md) already
preserves rank ties and runs native cleanup, bounded basis changes and
projections. Narrow candidates also feed search seeds and incremental
composition. Wide transformed outputs remain checked archives: there is no
automatic recursive wide recomposition or conversion to live u64 seeds.

The planner only needs factor equality, suggesting exact interning of complete
wide factor vectors into labels. However, its current 512-term limits and real
multiword parent expansion still need implementation and resource gates.
Forwarding labels as if they were factor masks would be incorrect. A future
wide-to-narrow feedback path also needs a separate durable outbox: the main
coordinator owns narrow intake, while the child owns composition queues.
None of these feedback extensions is claimed implemented by this change.

## Evidence and scope

Working reports are under
`/private/tmp/metaflip-seeded-basis-sweep-20260910`. Bulk tensors and binaries
stay outside the repository. The local evidence archive is:

```
~/.local/share/tungsten-metaflip/evidence/2026-09-10-seeded-basis.tar.gz
```

The sealed archive is 80,524,374 bytes with 5,544 manifest payloads and SHA-256
`65d757ffa78f2c836cd7a4e29242e138521f4b0cbad973813d330a0c6a4ccdd6`.
Cold replay from the copied evidence completed successfully; the manifest and
`cold-replay-report.json` are included.

It preserves inputs/intermediates, all completed projections, pricing plans,
96 full constructions, source pins, binaries and independent replay scripts.
The portable replay runs the 844 native gates, all 5,657 algebra/context checks,
every completed projection/cleanup/full tensor, and all 96 compositions. It
rechecks the selected materialized plans, not all 26,397 pricing-only plans.

The public binary was rebuilt with the actual Bitfile's release/native defaults.
Build base is `cf4ed3b15e7b62092ff61d358342e5d7759329ca`; this uses the local
compiler/runtime, not a clean bootstrap. No full local `rake`, canonical seed
promotion, publication or push is included. The six unrelated dirty files are
unchanged; their combined diff SHA-256 remains
`2f741028f621d98408d438dd598a8738b499710070aae691675a893a9bc8cf42`.
