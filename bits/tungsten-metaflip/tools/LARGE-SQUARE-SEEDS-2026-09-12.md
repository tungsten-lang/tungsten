# Large-square seed refresh — 2026-09-12

This imports existing results; it is not a new-rank claim. Search field is
GF(2), with bilinear tensor identities, not arbitrary commutative algorithms.

| Square | Previous generated start | New default / reference | Automatic bank | Downloaded ranks |
|---|---:|---:|---:|---|
| 8 | 329 | 329 | 4 | 343 |
| 9 | 529 | 486 | 1 | 486 |
| 10 | 651 | 651 | 4 | 651, 686 |
| 11 | 975 | 873 | 1 | 873, 960 |
| 12 | 1071 | 1068 | 4 | 1068, 1071 |
| 13 | 1575 | 1426 | 1 | 1426 |
| 14 | 1729 | 1725 | 4 | 1725 |
| 15 | 2139 | 2058 | 4 | 2058 |
| 16 | 2209 | 2209 | 2 | 2401 |

Bank size is the available startup bank with multiple workers and no explicit
seed/naive override; worker `i` takes bank entry `i % bank_size`. Fewer workers
may not use every bank entry. Literal duplicates are removed, but these are
not certified inequivalent isotropy classes. Rank ties remain useful starts.
Automatic alternatives must be within ceil(5% of leader rank); higher-rank
downloads remain explicit-only. Better durable checkpoints still win.

### Stronger historical local starts

The existing `block_composition_records.tsv` also records exact 13x13 rank
1402 and 15x15 rank 2008 witnesses, stronger than the imported public starts.
Both were recovered individually from local commit
`a0c14c3b08ea0a0a07745b0fc530266cd317e091`, checked against their recorded
SHA256 digests, and independently expanded by Ruby and Python. These are
previously found compositions, not new discoveries from this refresh.

`tools/recover_wide_local_seeds.py --repo /path/to/tungsten` converts them to
MFW1 and installs them only into `~/.tungsten/metaflip/checkpoints/gf2/`.
It never overwrites an existing checkpoint, fetches no archive, and writes
provenance alongside the recovered files. This checkout must retain the
pinned Git objects. Full coefficient-redistribution lineage remains under
review, so these two witnesses are **not bundled** in the runtime package.
With those local checkpoints, the 13x13 and 15x15 starts are 1402 and 2008,
respectively, with two near-best bank entries each; the table above describes
a clean installation without those local artifacts.

## Sources and field exclusions

- [Perminov catalog, pinned revision](https://github.com/dronperminov/FastMatrixMultiplication/tree/db560ca5811bc38d5a6d5c0a3ec4315937ceabce):
  13 result JSON files downloaded, 12 distinct exact certificates retained.
  The addition-reduced 8x8 file is a duplicate after expanding its circuit.
  Source and certificate digests are in `../lib/metaflip/manifests/wide-seeds.tsv`.
  The repository's MIT license is included. Raw downloads total about 24 MiB
  in `~/.cache/metaflip/upstream`, not in the Tungsten repository; normalized
  runtime tensors total exactly 1,316,280 bytes.
- [Lille catalog](https://fmm.univ-lille.fr/): cross-checked the individual
  square pages; for example [9x9 rank 486](https://fmm.univ-lille.fr/9x9x9.html)
  explicitly credits Perminov. The mirrored coefficient files have no clear
  redistribution license and were not imported.
- [matmulcatalog metadata at f3a7f0f](https://github.com/solven-eu/matmulcatalog/tree/f3a7f0f61b1005666c2cb03f98f2a16727604ea0):
  lower-looking Waksman entries are commutative-only; 12x12 rank 1040 has
  fields F3/Q/R/C, and 14x14 rank 1719 explicitly excludes F2. They are not
  usable GF(2) tensor seeds. The rank-1421 13x13 Perminov Q file contains
  coefficients `1/8`, so direct reduction is rejected. We make no assertion
  that no alternate characteristic-two realization of these ranks exists.
- 8x8 rank 329 and 16x16 rank 2209 are standard Kronecker consequences of the
  already downloaded Strassen rank 7 and AlphaTensor GF(2) rank 47 seeds:
  7*47=329 and 47*47=2209. The stronger defaults are retained rather than
  replaced by the higher ternary ranks 343 and 2401.

## Verification and use

`tools/import_wide_seeds.py` fetches only pinned data, checks every git-blob
hash, strictly parses exact coefficients/circuits, transposes W, and expands
the full tensor before generating canonical MFW1. No downloaded code runs.
`spec/wide_seed_import_test.py` independently replays all twelve certificates
through Ruby and tests field/type/circuit/corruption rejection.

`spec/wide_square_test.w` gates each chosen start and 41,000 moves per size;
the public CLI test independently checks tensors, reference ranks, bank sizes,
checkpoint preservation, explicit seeds, and interrupted mixed-width cycles.
The PTY test covers the shared visual layout, 120→80 resizing and clean quit.
The importer is offline tooling only; native startup performs exact checks
and does not invoke Python or access the network.
