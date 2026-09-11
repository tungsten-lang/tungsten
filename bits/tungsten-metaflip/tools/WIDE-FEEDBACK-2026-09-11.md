# Checked wide-output feedback and bounded search

The native refinement pipeline now returns eligible wide-format outputs to
narrow refinement/composition and live seed admission. This is an integration
improvement, not a new world record. The accompanying searches find one
verified local-table improvement; a stronger catalogue entry rules out its
promotion as a best-known result.

## Runtime change

After composition cleanup or an admitted wide basis/projection result, the
single child publishes a handoff when each factor width is at most 63 bits
and rank is at most 4,096. The record binds both complete representations:

```
MFW_FEED1 packedSHA narrowSHA n m p rank
```

The publisher rechecks the immutable packed object, conversion, full tensor
identity and narrow object. The main coordinator independently validates both
objects and their exact termwise conversion before writing an ordinary narrow
intake ticket. Only that coordinator owns intake and the feedback consumed
cursor. Rank ties are not discarded. Deduplication uses shape and full terms.

The outbox uses 64-record pages, a packed-identity index, append/index/counter
recovery, and acknowledgement only after durable intake. An intake-before-ack
crash can offer a seed again, but cannot create another intake ticket. This is
at-least-once seed presentation, not exactly-once live execution. A corrupt
handoff remains pending with a visible error; that consumer lane pauses until
repair/restart. Other work is not reclassified as successful feedback.

The coordinator considers at most one handoff per 250 ms and pauses at eight
pending refinement jobs or existing composition backpressure. Those are work
scheduling limits, not wall-time guarantees or disk quotas. Large witnesses
remain in the checked wide archive. Unsupported live shapes and oversized
live seeds still enter eligible narrow refinement/composition, without being
passed into incompatible worker states. No live shape allowlist was enlarged.

Matching supported shapes pass the existing near-best seed policy. A new
`wide_feedback_seed_uses` counter increments only after a live island accepts
the seed; consumption is reported separately. `METAFLIP_WIDE_FEEDBACK=0`
disables publication and pauses consumption without deleting saved work.
There are no new Python/Ruby runtime dependencies, GPU workers, or concurrent
queue writers.

## Focused verification

- 119 native harness invocations cover full-format conversion, bit 62, 64-bit
  archive-only behavior, square/rectangular initialization, rank ties, dedup,
  tail recovery, intake-before-ack replay, stop/disable, backpressure, page
  boundaries, and corruption. Pairing two individually valid rank-7 tensors
  as a false cross-format conversion is rejected, even with a valid page hash.
  A forced intake-index write failure keeps the handoff unacknowledged; after
  repair, restart recovers the saved ticket without duplicating it.
- Existing refinement regression: three jobs, 15 independently checked derived
  outputs, resume/dedup/cancellation and malformed-input rejection.
- Automatic wide queue: 169 contexts, including 36 basis contexts, 133
  projections, 14 changed rank ties, and two eligible outbox entries. The
  independent row-block oracle has 461 dense/sparse/grid comparisons.
- Public Bitfile build uses release/native defaults. Public square and
  rectangular start/stop/resume tests pass, as does refinement disabled.
- End-to-end regression: lift the existing 2x5x6/r47 tensor into a 2x5x7
  parent, run actual public composition/projection batches, then start the
  live 2x5x6 campaign. The r47 projection is used by a live island. Six other
  matching projections at r51/r52 are consumed but do not bypass the seed
  rank policy. The final six-second run consumes 18/18 handoffs and records
  one actual wide-feedback seed use. All worker children stop.

Example focused commands (all output directories must be new):

```
bin/tungsten compile bits/tungsten-metaflip/spec/wide_feedback_test.w --release --native --out /tmp/wide-feedback
python3 -B bits/tungsten-metaflip/spec/wide_feedback_test.py /tmp/wide-feedback --retain /tmp/new-feedback-check
bin/tungsten compile bits/tungsten-metaflip/spec/wide_transform_queue_test.w --release --native --out /tmp/wide-transforms
python3 -B bits/tungsten-metaflip/spec/wide_feedback_fleet_test.py bits/tungsten-metaflip/bin/metaflip /tmp/wide-transforms /tmp/new-feedback-loop
python3 -B bits/tungsten-metaflip/spec/refinement_fleet_test.py bits/tungsten-metaflip/bin/metaflip /tmp/new-public-feedback-check
```

These gates use the current local compiler/runtime, not a clean compiler
bootstrap. No full local `rake` suite was run. Early failed checks exposed a
square-versus-rectangular verifier mismatch in the test and an unsupported
live-shape assumption; both are now explicit regressions. The initial naive
live-loop fixture correctly failed to demonstrate seed use because its rank
was too high. The replacement fixture tests a genuine eligible rank tie.

## Search evidence

The 180-second multi-coordinate experiment completes 989 of 2,688 planned
contexts from 60 parents and 84 parent/target pairs. Each trial applies a
checked basis word, deletes two through six coordinates, and cleans after
each deletion. Independent cold replay checks all 4,231 steps and 954 distinct
final tensors; 948 representations are new to the prior study series. It is
a terminal bounded run, not an exhausted search family.

| Square | Best restriction found | Retained table |
| --- | ---: | ---: |
| 2x2x2 | 7 | 7 |
| 3x3x3 | 23 | 23 |
| 4x4x4 | 52 | 47 |
| 5x5x5 | 104 | 93 |
| 6x6x6 | 183 | 153 |

Two additional 12-second public runs use one low-priority CPU walker plus the
bounded background child, no GPU, on 3x4x7 and 4x5x6. Their primitive ranks
remain 64 and 90. Across both spools, 708 distinct cross-format-deduplicated
witnesses span 115 canonical shapes, all fully checked. These runs do not
exhaust their saved refinement/composition queues.

The automatic pipeline produces **11x16x28/r2910**, improving its frozen local
comparison r2963 by 53. Provenance is mixed composition ticket 27 producing
12x16x28/r3008, followed by transform ticket 9: delete coordinate zero on axis
zero and exact matrix cleanup. Output SHA-256:
`2c15f429dce05515ee74bc1ba86d0cf407329f9421aeaba2a9c4a04c12da28e7`.

This is **not a world-record claim**: the live
[Lille reference](https://fmm.univ-lille.fr/11x16x28.html), checked September 11,
lists r2894. The response is retained with SHA-256
`61b537db67c2f55a6046962cb56eebe505d9f05396a9bd0284a165efcafe24b5`.
It is comparison metadata, not an imported GF(2) construction or certified
leaf. No causal claim is made that feedback itself caused this gain: the
already-native projection lane produced it during the new runtime's search.

The deduplicated study-series rollup is **6,385 representations** including
166 original inputs, or **6,219 non-input representations**. The short public
runs add 681 beyond the 5,704 after square restrictions. These are distinct
representations, not improved-shape or record counts. Artificial test fixtures
are excluded.

## Retention and scope

Bulk spools, native binaries, pinned sources, reference response, and independent
audits are kept outside the checkout. Square evidence is sealed as:

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-square-restrictions.tar.gz
8,808,220 bytes; 8,461 payloads
SHA256 08b805d1b21caf2f63983ef0c7ae8d84381e8688d68c0876b79944dd8627256d
```

Feedback/search evidence includes independent cold replay of all six saved
composition/transform spools, native verification of the r2910 candidate,
and the final I/O-failure and public live-loop regressions:

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-wide-feedback.tar.gz
15,695,643 bytes; 10,238 payloads
SHA256 979a10a86b12f54aee711c7e30672b06759e285ef5b44d724f09308adb9a3acf
```

Both archives were read back and every manifest payload hash rechecked.

Search-run executable SHA-256 (before the final I/O-failure guard):
`e5ac54222293af3dea1347c8ee630d3d0c90f5311171e2435871cd2dc4061409`.
Final focused feedback harness SHA-256:
`4d049cd45e1eb6b4710b0c2a72136a2932fc4545c4d0ad9bedff82ef4bb3d23f`.
Final public executable SHA-256 after the I/O-failure guard and repeated
public lifecycle/live-feedback tests:
`adbe7c04e3bb56ae257c9cc6f95d850914f1e807c1244e43a5af2521e4fcc999`.

No canonical seed promotion, publication, GPU search or performance claim is
included. Unrelated compiler/runtime/spec edits remain untouched; their
seven-file diff hash is
`318ba7d82e3752664e353ae1fb672b0b8a493b05f3cfaeb19f241f68462a27b3`.

## Follow-up: live-parent and larger-tensor refinement

No new retained rank or world record. This follow-up tests newly generated
representations from the live runs above, rather than repeating the original
166-parent study. It does not enable another default fleet lane. The withdrawn
profiling request was not executed.

The current [Lille table](https://fmm.univ-lille.fr/) was refreshed (5,426
formats). The [catalogue](https://github.com/solven-eu/matmulcatalog) snapshot
still matches `solven-eu/matmulcatalog` commit
`f3a7f0f61b1005666c2cb03f98f2a16727604ea0`; its JSON SHA-256 is
`df3be3959d449ba715834211a5023f41a90b43f7f9a129c8fbea1bc88d8ca419`.
The small source corpus was already imported in the September 6 study, so no
duplicate import campaign was run. Retained constructive bounds, catalogue F2
metadata and Lille ranks remain separate fields. The minimum reported rank is
used only to order work conservatively, not as an admitted GF(2) leaf or a
field-transfer theorem. For example, Lille lists 3x3x6/r40, whereas the pinned
catalogue's minimum F2-labelled rank for that shape is 42.

From the recent live spools, select all 197 distinct witnesses within two
terms of the retained bound, with factor width <=63 bits and rank <=512.
They cover 28 canonical shapes. Every input is independently reconstructed
and native-full-verified. All 12,411 parent/scale plans complete, covering
423 targets; none improves the retained bound. A round-robin shortlist of
32 full compositions covers all 28 parent-shape families, with no cleanup
reduction.

A 180-second native seeded-basis sweep completes 2,249 of 3,152 configured
contexts, with 11 or 12 contexts for every input. Independent row-equation
replay checks all 5,714 actual algebra steps, including cache reuse and
context lineage. There are 122 distinct endpoints not among the cohort's
inputs, across nine shapes; no native verification deferrals or retained-rank
gains. This is a terminal bounded sample, not an exhausted basis search.

All 7,686 scale plans for those endpoints complete. Nineteen target minima
are cheaper than the original live cohort. Both sides of all 19 comparisons
are fully expanded with the same checked leaf bank, independently substituted
and tensor-verified, then cleaned. All 19 improvements survive, saving 1--16
terms, but none beats the retained bound. Examples:

| Target | Original live cohort | Basis-derived | Retained |
| --- | ---: | ---: | ---: |
| 3x9x32 | 696 | 680 | 645 |
| 6x12x16 | 752 | 744 | 736 |
| 6x9x12 | 435 | 433 | 433 |
| 8x9x9 | 434 | 433 | 432 |

These are cohort improvements, not newly best-known shapes. An additional
32 diverse derived compositions also pass full checks. In total this covers
102 full compositions and 20,097 checked price plans; price-only cases are
not claimed expanded. None of the 102 full compositions decreases rank in
cleanup. All 218 selected one-coordinate projections also complete, with
independent coordinate contraction, matrix cleanup and complete tensor checks;
none improves the retained bound.

Finally, select 25 newly expanded tensors across 20 shapes, rank <=1,000 and
within two terms of the retained bound, and refine the larger tensors directly.
All 400 configured contexts complete in about 81 seconds. They produce 166
additional cohort endpoints, with no retained-rank gain or verification
deferral. This tests the post-expansion stage instead of inferring that a
small parent's refinement result settles its larger descendants.

Decision: keep seeded diversification opt-in. It changes useful composition
structure, but this sample does not justify spending extra default work on
every candidate. Preserve the checked rank ties for later projection and
context-specific selection. Do not infer a search-space impossibility from
these finite negative rank results. No canonical seeds, runtime defaults,
GPU work, performance claims or public record claims were added.

All new bulk evidence remains outside the checkout. Working root:
`/private/tmp/metaflip-live-study-evidence-20260911`. Its portable cold checker
is `package.py audit`; it replays algebra, full compositions and projections
against copied independent oracles and pinned native verification binaries.
Cold replay passes all 7,667 algebra steps, 102 full compositions and 218
projections. It also rechecks every distinct admitted endpoint with the
native full-tensor verifier and the independent integer reconstruction.
The final study-series rollup is **6,957 representations**, including the
166 original inputs, or **6,791 non-input representations**. This follow-up
adds 572 representations beyond the prior 6,385; intermediate scratch
states, duplicate contexts and price-only plans are not counted as additions.

Sealed evidence (every manifest payload read back and hash-checked):

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-live-parent-followup.tar.gz
12,336,587 bytes; 2,924 payloads
SHA256 b65e4b48effdc67747d0b7583396892076b05e34ed90666a09c0e4d224b46254
```

All owned search and audit processes are terminal. No full `rake`, push,
publication or canonical seed promotion was performed. The seven-file
unrelated diff hash above is unchanged.
