# Bounded exact wide-tensor feedback loop

`search_wide_auto_loop.py` closes the offline handoff that was previously
manual: verified parent → basis/projection candidates → native directed walks
→ exact admission and GF(2) closure repricing → Strassen composition → queued
descendants for another bounded round. It retains different full-term
representations, including useful rank ties. Each queued tensor is checked by
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

Matched control: starting from the packaged `7×16×12/r873` witness, with
three 100M walks and nonce base `2026092502`, the loop independently recovered
the certified r872 witness (SHA-256
`8117a6eab7d35eefae49e4ca4165b3ca329e2880ddd91581443ea5caafc93fe8`)
and materialized its exact 14×24×32/r6104 Strassen product. The first basis
beam spans distinct axis orders; otherwise two reverse variants consume both
slots and the successful mode-12 neighborhood is skipped. A focused fake-walk
test checks exact admission, projection, composition, and this basis ordering.

This is **not** a live `bin/metaflip` arm. It currently composes only with the
exact GF(2) 2×2×2/r7 partner, not arbitrary block sums or the entire parent
portfolio. Those extensions need matched yield and responsiveness evidence
before automatic live-fleet integration.
