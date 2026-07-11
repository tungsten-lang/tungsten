# Mixed escape portfolios

`escape_portfolio.py` builds rank-aware seed banks from exact GF(2)
tensor-zero identities. It complements the fixed-rank split portfolio inside
the Metal relay: each slot stores a complete scheme, so generic splits,
fixed-cube breaks, C3 orbit-splits, polarizations, and depth-two compositions
can coexist even though their rank deltas differ.

Every move is a parity toggle. Zero-factor terms vanish, duplicate terms
cancel, and complete output term sets are canonicalized. Depth-two paths are
therefore normalized by their result: commuting paths, collision variants,
and an involution followed by its inverse cannot occupy duplicate slots.
Before a slot is serialized, `bench_decomp.verify` reconstructs the full
matrix-multiplication tensor independently of the escape identity.

The default 48-slot mix contains the base plus four representatives of most
families (three for the last family):

- `split`, `break`, `orbit-split`, `polarize`;
- `split+split` and `break+split` asymmetric excursions;
- all four two-step combinations of `orbit-split` and `polarize`; and
- `orbit-split+break` and `polarize+break` transitions from the C3 quotient
  into the ordinary flip graph.

The public `entries_from_schemes(base, schemes, n, recipe_label)` function is
the import path for identity miners and meet-in-the-middle surgery tools. It
independently verifies, canonicalizes, and deduplicates arbitrary candidate
schemes before `write_bank` serializes them.

## Reproduce the tracked banks

```sh
cd benchmarks/matmul/metaflip
python3 escape_portfolio.py build \
  matmul_5x5_rank93_d1155_gf2.txt 5 escape_bank_5x5_mixed.jsonl \
  --count 48 --per-step 16
python3 escape_portfolio.py build \
  matmul_6x6_rank153_d2574_c3_gf2.txt 6 escape_bank_6x6_mixed.jsonl \
  --count 48 --per-step 16
python3 escape_portfolio.py verify escape_bank_5x5_mixed.jsonl
python3 escape_portfolio.py verify escape_bank_6x6_mixed.jsonl
```

Each bank has 25 C3-closed slots and 23 symmetry-breaking slots. The 5x5 bank
spans ranks 93 through 107 and densities 1155 through 1374. The 6x6 bank spans
ranks 153 through 167 and densities 2574 through 2766. The tracked 6x6 C3 seed
is the pre-GPU rank-153, density-2574 frontier; the current density-2508 seed is
exact but no longer C3-closed, so it cannot seed the quotient half by itself.

## Hybrid and Metal runs

`hybrid_escape.py run` generates and compiles a C3 Tungsten walker, thaws its
result with an exact fixed-cube break (or an ordinary split when no fixed cube
survives), and then runs the generated bucketed
ordinary Tungsten walker. Both handoffs undergo full independent tensor
reconstruction. Slot zero is included by default as the base control; use
`--exclude-base` to start with the first non-base C3 escape. For example:

```sh
python3 hybrid_escape.py run escape_bank_5x5_mixed.jsonl /tmp/hybrid \
  --slots 1 --exclude-base --c3-moves 1000 --full-moves 1000
```

In the initial M5 Max smoke, an orbit-split slot went rank 98 -> 93 in the C3
phase, thawed to 94, and returned to rank 93 at density 1181 in the full phase.
The C3 and full native runs took 0.161 s and 0.133 s; their one-time release
compiles took 5.443 s and 5.451 s.

`hybrid_escape.py metal` compiles a dimension-specialized, one-round real Metal
relay for one bank slot and independently verifies any result on the CPU:

```sh
python3 hybrid_escape.py metal escape_bank_5x5_mixed.jsonl /tmp/metal5 \
  --slot 3 --steps 10000 --walkers 256 --escapes 1
python3 hybrid_escape.py metal escape_bank_6x6_mixed.jsonl /tmp/metal6 \
  --slot 3 --steps 5000 --walkers 128 --escapes 1
```

Measured results:

- 5x5 orbit-split rank 98, density 1185 -> exact rank 93, density 1156 in
  0.648 s (256 lanes x 10,000 moves); output is non-C3, fixed=3, flip-pairs=13.
- 6x6 orbit-split rank 158, density 2610 -> exact rank 153, density 2540 in
  0.539 s (128 lanes x 5,000 moves); output is non-C3, fixed=3, flip-pairs=22.

These runs validate the hybrid route and native-i64 Metal path. They did not
set a rank or density record: the tracked density leaders are 5x5 d1155 and
6x6 d2508 after the later cooperative-SIMDgroup campaign.
