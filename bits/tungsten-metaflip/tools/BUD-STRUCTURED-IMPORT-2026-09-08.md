# Import structured parents before spending more flips

The new offline `structured_exp_import.py` imports rectangular integer `.exp`
decompositions, checks the complete integer tensor, reduces coefficients modulo
two, normalizes the requested dimension orientation, and independently checks
the resulting GF(2) tensor. It does not change the fleet, clear redistribution
rights, or declare a record. The old signed-square importer is unchanged.

Two concrete source-format issues motivated this tool:

- `234.exp` in the pinned source stores shape **4x2x3**, not 2x3x4. Filenames
  label a tensor up to dimension permutation; they are not storage layouts.
- `kd4bccb937e46702-238-40-mod0.exp` contains non-ternary coefficients such as
  `2b21`. They must be checked over the integers before reducing modulo two.

The parser accepts only products of three parenthesized integer linear forms
in one-digit `aij`, `bjk`, `cki` trace coordinates. Both `2a11` and `2*a11`
are supported; source text is never evaluated. Missing operators, wrong
variable families, zero forms, inconsistent dimensions, wrong expected shapes,
and integer-invalid/GF(2)-valid sources are rejected. C coordinates are
transposed into the worker's output-row-major convention. Duplicate projected
terms cancel by parity; zero projected factors are dropped.

## Reproduce an import

Run from the repository root, using a previously recorded source digest:

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/structured_exp_import.py \
  --source /path/to/234.exp --shape 2x3x4 \
  --sha256 e9ff3fad5810e5925319cdd999e5c0bb9201a2cb634dd03e4b80a57a2647ba29 \
  --output /tmp/structured-234
```

The output directory must not exist. Source bytes are read once and checked
against the supplied hash. Output includes `source.exp`, a full `tensor.txt`,
and `report.json` with source/target orientations, source/tool hashes, integer
term count, projected rank, and independent verification. The nested verifier
hash refers to its normalized `R u v w` rows; the top-level `sha256` refers to
the exported rank-header certificate. `--source-url` records provenance only;
the tool never fetches it. License review remains a separate gate.

Focused tests, including all 36 source/target permutations of 2x3x4:

```sh
cd benchmarks/matmul/metaflip
nice -n 10 python3 -B -m unittest \
  test_structured_exp_import test_verify_composition_recipes \
  test_signed_projection_audit
```

Result: **16 tests passed**. Fixtures are synthetic, not redistributed
upstream algorithms. Negative cases include source-hash mutation, invalid
integer tensors which would pass mod two, malformed syntax, and output reuse.

## Bounded corpus replay and composition

Imported all 32 files in the authors' [structured directory](https://github.com/mkauers/matrix-multiplication/tree/12c26b29a5458e173813911fb4f2c2865fba841e/structured),
pinned to commit `12c26b29a5458e173813911fb4f2c2865fba841e`. Each download was
checked against the Git blob hash in the pinned directory listing. The full
upstream GPLv3 license is retained locally. No imported tensor is committed.
These are literature inputs, not discoveries by this search.

All 32 integer identities and GF(2) projections passed. The independent GF(2)
replay covers **2,193 terms and 46,354 support-pair XORs**. Four literal tensor
identities were already present; 28 new ones increase the parent corpus from
15,482 to **15,510**. These are shape-plus-term identities, not isomorphism
classes or distinct algorithms modulo arbitrary basis changes.

Full recursive recomposition through side 32 gives **131 lower local prices**,
with largest reduction 27. None newly crosses the pinned reference screen,
and no main-square rank improves. That reference screen is a bounded,
mixed-field construction comparison, not a fresh common-field optimality or
novelty theorem. The most useful imported parent was `237.exp`, a rank-35
2x3x7 presentation used directly by 21 improved formulas. Its full identity
and grouping structure matter; its primitive rank is already known.

Five representative gains were expanded and independently replayed:

| Shape | Previous local | Checked rank | Pinned reference |
| --- | ---: | ---: | ---: |
| 14x25x28 | 5657 | 5630 | 5578 |
| 10x15x28 | 2484 | 2476 | 2476 |
| 8x21x27 | 2742 | 2732 | 2732 |
| 14x20x20 | 3252 | 3247 | 3247 |
| 8x18x24 | 2091 | 2076 | 2040 |

The independent recipe audit checks **34 tensors, 32,290 terms, and
4,119,926 support-pair XORs**, including all five expanded outputs. The other
126 new prices remain arithmetic recipes, not newly expanded certificates.
Three shapes overlap the previous 72-shape bounded cohort: its deduplicated
total is now **200 shapes**, with **11 expanded outputs and 189 recipes**.
The scoped reference-crossing shortlist stays at 41; none is thereby a
confirmed world record. This is not the older campaign's separate tally.

## Holdout falsification

Before importing these parents, the rank-19 2x2x5 endpoint behind 5x32x32 at
3430 received a matched holdout study. The control and all seven nonempty
subsets of its three disjoint U-quartets each received 32 trials, 64 chunks,
65,536 attempts/chunk, observation interval 1,024, debt two, density slack four,
and RNG 912149. Held cost was the sum of elementary-cover prices, not an
assumption that several quartets form one elementary block.

All eight arms stayed at 3430 after **1,073,741,824 total attempts**, with no
holdout cancellations. Independent replay checked group maps, full winners
and endpoints, scores/accounting, **502 tensors, 9,576 terms, and 46,216 pair
XORs**. This is bounded negative evidence, not proof that holdouts cannot help.
No new holdout operator or default policy was added.

All work used one low-priority worker; no GPU/fleet run was started. Local-only
evidence is retained at
`benchmarks/matmul/metaflip/structured_import_audit_2026_09_08/`, including
sources/license, full products, checkers, manifests, and compressed pricing
inputs. Product replay is self-contained; the full pricing driver still uses
the pinned earlier local ancestry. The next useful bounded target is the
composition structure of the thinly represented 2x3x7 family, with the imported
parent as a control and full-identity endpoints retained.
