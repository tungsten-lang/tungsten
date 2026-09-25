# Bounded exact wide-tensor feedback loop

`search_wide_auto_loop.py` closes the offline handoff that was previously
manual: verified parent → basis/projection candidates → native directed walks
→ exact admission and GF(2) closure repricing → Strassen and shared-factor
pair composition → queued descendants for another bounded round. It retains
different full-term representations, including useful rank ties. Each queued tensor is checked by
the Python exact gate and an independent Ruby full-tensor reconstruction;
pricing and public comparison tables never substitute for those gates.

The loop requires an exact MFW seed, a pinned GF(2) catalog, and a compiled
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
The walk budget is divided across requested rounds, reserving slots for
descendants. Within a round, the first projection and two independent basis
orders precede extra variants; if that projection is farther above its shape's
current price, one basis order leads, but the projection still receives the
second slot. Frontier states are visited in
price-gap order and round-robin, and a valid basis seed remains eligible for
the next round even when its walk returns the same state. Thus a wide first
beam or one descendant cannot consume the whole feedback budget.
Every retained projection that strictly improves its shape's round-start
price is now independently verified, archived, composed, and offered to the
next frontier without consuming a walk slot. Distinct tied representations
remain eligible for walks; the projection beam still bounds how many are
walked. This is automatic within the offline campaign, not in `bin/metaflip`.

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
it found no rank improvement. Live-fleet integration needs matched yield and responsiveness
evidence, plus multiword parent support in the native composition intake.
