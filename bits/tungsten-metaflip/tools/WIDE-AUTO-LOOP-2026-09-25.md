# Bounded exact wide-tensor feedback loop

`search_wide_auto_loop.py` closes the offline handoff that was previously
manual: verified parent → basis/projection candidates → native directed walks
→ exact admission and GF(2) closure repricing → Strassen and shared-factor
pair composition → queued descendants for another bounded round. It retains
different full-term representations, including useful rank ties. Each queued tensor is checked by
the Python exact gate and an independent Ruby full-tensor reconstruction;
pricing and public comparison tables never substitute for those gates.

The loop requires an exact MFW seed (raw `.mfw` or a checked-in
`.mfw.gz.b64` certificate), a pinned GF(2) catalog, and a compiled
`tools/wide_rect_walk.w` binary. Example:

```
python3 tools/search_wide_auto_loop.py \
  --seed /path/to/verified-seed.mfw \
  --catalog /path/to/pinned-catalog.json \
  --walker /path/to/wide-rect-walk \
  --output-dir /path/to/new-output-directory \
  --rounds 2 --max-walks 6 --steps 100000000
```

The output directory must not exist. `manifest.json` checkpoints each admitted
tensor, its source, exact rank, prior GF(2) price, and finite 2..32 closure
delta. A running/interrupted manifest is not a negative result or a completed
certificate. `record_claim` is always false. By default, a composed tensor
above rank 3000 is materialized and checked but not queued for another walk;
`--max-search-rank` raises that workload cap explicitly.
Admission rows also record the pinned catalog's `external_best_rank`, source,
and signed rank gap when available. These are comparison metadata only: the
external rank may be over another field and neither certifies a GF(2) tensor
nor establishes a world record. The campaign never uses it as its GF(2) price.
The walk budget is divided across requested rounds, reserving slots for
descendants. Within a round, the first projection and two independent basis
orders precede extra variants; if that projection is farther above its shape's
current price, one basis order leads, but the projection still receives the
second slot. Round zero visits the original source first; later frontier
states use price-gap order with composed states ahead. Walk slots are assigned
round-robin, and a valid basis seed remains eligible for
the next round even when its walk returns the same state. Thus a wide first
beam or one descendant cannot consume the whole feedback budget.
Every retained projection that strictly improves its shape's round-start
price and is no worse than its current live price is now independently
verified, archived, composed, and offered to the next frontier without
consuming a walk slot. Distinct tied representations remain eligible for walks;
superseded projections are skipped, and the projection beam still bounds how
many are walked. This is automatic within the offline campaign, not in
`bin/metaflip`.

Newly composed frontier states now offer one direct native walk before their
projection and basis neighborhoods. The scheduler reserves at most one such
walk per round, never directly walks the original source by this rule, and
starts round zero with the source's first projection/basis choice. Each exact
composed representation gets at most one direct walk within a campaign; a
new rank or representation can be offered again as a new state. This closes a
gap in the cold loop without spending every slot on direct continuations.
Matched source controls tied at 8×16×13/r1037, 7×13×16/r962, and
20×22×25/r6076, while the archived 13×15×23/r2662 exact composition has a
first direct-walk drop to r2659. These observations justify provenance-aware
scheduling, not a claim that direct walks usually win.

Matched control: the earlier projection-first schedule recovered the certified
r872 witness from the packaged `7×16×12/r873` source in three 100M walks. With
price-gap ordering, the same source and nonce base `2026092502` reached a
different exact r871 representation on its first mode-6 walk and materialized
the 14×24×32/r6097 Strassen product. This scratch representation does not
improve the price beyond the three archived r871 witnesses; its best
one-coordinate projections also remain above their current prices. The first
basis beam spans distinct axis orders so reverse variants cannot consume both
slots. Focused tests check exact admission, two-round feedback, projection,
composition, and ordering.

Four-walk scheduling control (two 20M-walk rounds, same seed and nonce base):
the former basis-first ordering spent both first-round slots on basis variants
of the exact 11×8×15/r857 seed. Interleaving admitted and walked a verified
11×8×14/r825 projection in the second slot. It remained 21 above that child's
local price and neither schedule found a further rank drop. The known
7×16×12/r873 mode-6 control still reached exact r871 in one 100M walk and
materialized its 14×24×32/r6097 Strassen product. These are local scheduling
checks, not new records.

This is **not** a live `bin/metaflip` arm. It currently composes only with the
exact GF(2) 2×2×2/r7 partner or the projected 2×3×3/r15 pair leaf, not
arbitrary block sums or the entire parent portfolio. The pair arm uses all
three shared-factor axes, full multiword factors and exact tensor admission.
It replays the archived 4×7×4/r85 parent to 12×7×12/r651 with 38 shared
pairs; a one-step walk control found no new rank. A rank-only screen of 301
checked-in wide certificates and 4,326 local scratch MFW files found no
strictly better current pair price in the 2..32 shape range. That finite
screen is not a stopping theorem: equal-rank descendants may still be useful
walk seeds. A two-round, two-walk replay chose a projected 8×13×8 child of
an exact composed parent for the second walk, establishing actual feedback;
it found no rank improvement. Folding this entire portfolio loop into the live
fleet still needs matched yield and responsiveness evidence and broader partner
support than the native queue's existing bounded multiword pair arm.

The separate native cold transform queue already runs bounded basis, projection,
walk, and eligible pair-composition tasks, though not this archive-wide portfolio
loop. It now offers verified rank ties to pair composition, not just the single
best-rank identity. A matched replay used two exact 4×7×4/r85 representations:
one had 32 shared pairs on the useful axis and composed to exact 12×7×12/r669;
the other had 38 pairs and composed to exact r651. The native r651 output was
independently checked in Python and Ruby. Its source is the SHA-256 object
`8b3e5862d6400aab50874bf928abe42bd7b962d95143e0d0e51db0bc81c3c8be`
in the `2026-09-08-compact-parent-projections.tar.gz` release asset, whose
manifest says `redistribution_cleared: false`; no source tensor is bundled here.
This validates downstream utility for that tie, not a general yield claim.

A completed two-round, six-walk cold campaign from the same verified r651
composition projected an exact 12×7×11/r620 child and walked a basis rewrite
to r619, improving that shape's local GF(2) price from r624. The final
admission reduced 14 finite-closure prices; the compact four-state lineage is
retained outside the repository because its source archive is not cleared for
redistribution. Direct and ten distinct basis-neighborhood continuations of
r619 found no further drop in their stated finite budgets. Neither result is
claimed as a world record.

The replay path is parent object `8b3e5862…`, native pair axis 2 to
12×7×12/r651 (`fa204838…`), mode-7 projection of axis 2 coordinate 10 to
12×7×11/r620 (`31d91e61…`), mode-6 basis rewrite (`31456734…`), and a
10,000,000-move directed walk with nonce 251112 to r619 (`444d5d8f…`).

A later two-round control from the checked-in 19×25×27/r7144 parent admitted
19×24×27/r6871 as an exact projection, walked it to r6841, projected that
state to 19×24×26/r6725, and walked again to r6683. A separate 100M-step
continuation of r6841 reached an independently checked 19×24×27/r6827;
another 100M-step continuation found no further drop. The five retained
witnesses and their projection lineage are replayable in
`certificates/impact-grandchildren-20260925/`. This run exposed a scheduler
edge case: a later source could offer a projection below the *round-start*
price but above a new *live* price. The admission gate now skips such
superseded projections while preserving equal-rank alternative representations.

Two further one-round controls followed the public-bound leads: the exact
19×24×29/r7236 parent projected to 19×24×28/r7005, walked to r6994 and
continued to r6990; the 16×23×23/r4743 parent projected to 16×22×23/r4625
and walked to r4618. A 100M-step continuation of the latter did not drop.
The five retained witnesses are replayable under
`certificates/catalogue-projection-leads-20260925/`. The two final GF(2)
ranks are numerically below the Lille catalogue entries checked on
2026-09-25, but no cross-field or global record claim is made.

The next bounded campaign took 20×23×24/r6005 through an exact
20×23×23/r5924 projection, a 50M-step walk to r5885, and a 100M-step
continuation to r5883. The stronger 20×22×24/r5851 and 19×23×24/r5894
projections were retained from other checked-in parents. Their complete
witnesses and replay are under
`certificates/20x23x23-catalogue-lead-20260925/`.

The loop now accepts compressed checked-in certificates directly as seeds.
`retain_wide_auto_loop.py` exports only the best improved shape states and
their parent chain from a completed campaign, checking every tensor again in
Python and Ruby. A two-round, two-walk replay from 20×22×25/r6076 retained
four improved child shapes, led by 19×21×25/r5718. Two additional direct
continuations reached r5689, then a third 100M walk tied.
An exact mode-6 neutral basis rewrite of the r5689 child reopened the walk:
50M and 100M moves reached r5685 and r5683. Other tested basis orders and
continuations tied. A mode-10 rewrite of r5683 followed by 50M moves reached
r5682; other tested orders tied. The compact replay in
`certificates/20x22x25-auto-loop-20260925/` contains 14 checked tensors
under 3 MB. A final finite 2..32 GF(2) rank-only closure scan shows 10
improved prices and 839 summed rank units. The six derived price changes still
need exact materialization before being tensor witnesses; no retained child
crosses its pinned external comparison.
