# Namespaced Metaflip runtime

This directory is the single immutable runtime root used by the public
Metaflip executable:

- `scheme.w`, `verify.w`, `compose.w`, `fleet.w`, `rect.w`, `tui.w`, and
  `paths.w` define the major subsystems.
- `fleet/`, `rect/`, and `strategies/` contain coordinator and search modules.
  `rect/cpu_pool.w` keeps one OS thread per rectangular island across campaign
  epochs; workers reread their state slot after each barrier so rebases and
  reseeds remain visible without thread churn. The `<2,2,9>` profile reserves
  at most one cold 8,000-move split-cadence lane; a one-worker portfolio child
  alternates it with the ordinary 2,000-move lane across exact restarts.
  Inside the adaptive 7x7 campaign, the embedded 334/344 GPU children use the
  durable component best as slot zero and low-discrepancy rotate every other
  registered frontier/shoulder door. Launch tickets advance only after a
  successful dispatch, so a transient worker failure cannot skip a basin.
  `strategies/rect_block_interior.w` runs one exact seam/shared-factor probe on
  a rotating snapshot beside each rectangular CPU tranche. Its adaptive
  cadence bounds join overhead while rank-neutral endpoints replace only that
  island, preserving the rest of the sticky-door population.
- `fleet/provenance.w` defines the bounded square-best lineage record used by
  additive status fields and the atomic `<best>.provenance` latest-event
  sidecar. It records CPU island/door/zone and worker moves, GPU slot/role/pool
  mode and launch seed, or rectangular composition source without changing
  the native TUI.
- `strategies/rect_catalyst_lift2.w` and
  `strategies/macro_double_annihilation.w` retain the exact target-directed
  setup/trigger/cleanup compilers. They are bounded offline scouts, not default
  fleet lanes: their real-frontier decision screens found no useful endpoint.
- `strategies/rank_one_completion.w`, `rank_two_completion.w`, and
  `rank_three_completion.w` form the computed exact residual-completion ladder.
  They are allocation-stable offline recognizers and endpoint compilers; the
  matched packaged-frontier screens found no useful production-pool signal.
- `kernels/` contains the canonical pure-Tungsten runtime workers. Generated
  Metal sources and libraries are redirected to the writable worker cache and
  must never appear here.
- `seeds/gf2/` holds the exact starting, frontier, shoulder, and explicitly
  experimental schemes
  selected by the square and rectangular production profiles.
- `manifests/seeds.tsv` maps every operational seed to its digest and attributed
  path in the separately curated `tungsten-metaflip-results` corpus.
- `manifests/runtime-sources.tsv` records the exact Tungsten source closure.
- `SHA256SUMS` covers every file in this subtree other than itself.

These seeds are operational inputs, not a second results corpus. New fleet
discoveries belong in `~/.tungsten/metaflip/` until independently verified and
promoted to the public results repository.

The 7x7 hot default is the exact rank-247, density-3094 three-flip endpoint.
A NUMA-local CPU shard found a four-flip d3096→d3095 path after about 735.3
billion moves. Its first three legal flips already give d3094, so the final
density-worsening move is omitted. The result is a three-term exchange at
support distance six from d3096. Independent pure-Tungsten and host-side full
coefficient gates agree on rank and density. The d3096 parent and a
structurally distant d3098 scheme remain the next frontier seeds so lower
density does not erase basin diversity.

The affine-code frontier slot now uses the final Runpod campaign's exact
rank-247/d3094 child from pod `aack78ni07p1uh`, epoch 257/group 8177, source
commit `1dfc4321f964a0ca4eca75e8c0870f8692d565b0`. It is support distance six
from the packaged epoch-3306 d3096 parent and 396 from the unchanged hot d3094
default. Forty-eight canonicalized matched four-million-move trials tied the
incumbent 48/48 and beat the parent 48/0/0, so only that active basin slot is
replaced; the parent remains in `ffp_experimental_seed_paths(7)`. Raw and
order-independent term-multiset SHA-256 are respectively
`ddf710feced82ece388d9e368f9ad4bcf4da08d0583c4b17ab34a8a5e1accb71`
and `d71bbeb41d5da88264475eb412baca85d099764fa3a1fce9474cffc78b7cfee8`.

The active beam-far slot is the d3096 CUDA presentation harvested at Runpod
epoch 1849; it is a three-term exchange from its retained d3098 provenance
parent and saves two density bits. Its term support remains disjoint from the
active affine-code lineage described above, so the two slots preserve their
independent basins.
The final C013 continuation endpoint is exact rank 247/d3486 and now owns the
active C013-density frontier slot. Runpod epoch 1965 reached its identical
support in three of 24 canonical 4M-move trials from d3542. It is distance 20
from the former active d3492 child and 42 from d3542; a direct continuation was
locally terminal. The d3492 child and d3496 closure remain in
`ffp_experimental_seed_paths(7)` for explicit replay. Raw, term-multiset, and
D3/reversal hashes are `dfab762a6150c274b670f67f6169d3635c32974c0be106482717b94fae149b05`,
`52284f28e3886fe20b848ddd81d57993dbd1566de11c13cce8875c4729ffbef3`,
and `4873e956b1f3df815c250ab99fceb4ee9f3dd18c230fea8b5985e9f4817952ec`.
Its coarse MAP descriptor collides with affine d3094; objective ordering keeps
the affine scheme in that niche while d3486 remains a frontier/archive root.

Runpod epoch 1965/group 6417's exact d3542 certificate replaces d3538 as the
single `ffp_low_quota_seed_paths(7)` source appended after the 16-slot archive
is frozen. Across 24 canonical 4M-move trials it beat d3538 24/0/0 and d3492
23/0/1 and produced d3486 three times. It is also CUDA source 3; d3538 remains
explicit provenance, while the CPU frontier still retains its d3554 C013 root.
The cold schedule remains exactly 1/17. Raw, term-multiset, and D3/reversal
hashes are `bc0d913f34d0b733436059e16775bbff3c8f29e3306bd5b8e29de4f05a05b676`,
`6a54c3e5388784485afa3a10814a9e41658ff7456c339c3e01e1c487fe6e4f6c`,
and `dbd111c632e27812ddddac7300e6d4842a68340248842dce65c825f8eb7c9a24`.

`strategies/delta_components.w` implements support-component peeling. It
builds the bounded symmetric difference of two independently exact-gated
parents, connects terms whose Cartesian supports intersect on all three axes,
and tests each proper component from both bases. Every component relation and
child is reconstructed over all `n^6` coefficients. The d3096/d3095 fixture is
a ten-term `6+4` split and deterministically yields the packaged d3094 term
set. The coordinator invokes it only for a same-rank density improvement with
at most 64 changed terms; the single differential child invokes it before
full nullspace elimination. There is no ordinary CPU or GPU hot-loop cost.

The heterogeneous adaptive pool also rotates the mode-locked exact closer and
the debt MITM worker. Block-interior selection is permanently folded into the
existing exact three- and four-term span engines, where one quarter of
neighborhoods are cut/seam-directed rather than paying for a duplicate worker.

## AWS campaign shoulder provenance

Five exact endpoints from EC2 instance `i-0ecf109ded102072b`, campaign
`aws-world-record-20260721`, were independently expanded and checked against
every GF(2) target coefficient. Four are novel restart/archive inputs. The
remaining endpoint, `near1_16`, has the same normalized term multiset as the
existing public d2946 density leader; runtime packaging therefore uses that
canonical term order and leaves the AWS row permutation only in the local
cloud harvest. Source paths are relative to `metaflip-world-record-20260721`.

| Runtime seed | Original campaign source | Runtime SHA-256 | AWS raw SHA-256 | Role |
| --- | --- | --- | --- | --- |
| `matmul_7x7_rank248_d2946_live_density_leader_gf2.txt` | `7x7/near/n5-s00/near1/near1_16.txt` | `e956780eecce9ce0d7aee87ebc0a2f97748bcbd5559391bc34bb0c2e857a98ff` | `74d3327da51cd046fd1a4a95e8104a08ff7eb0287e94c21f862aded6831d0395` | canonical +1 density shoulder; AWS term-order rediscovery; support distance 495 from r247/d3094 |
| `matmul_7x7_rank248_d3092_aws_near1_local_gf2.txt` | `7x7/near/n5-s00/near1/near1_00.txt` | `690825311a714eac941ae6f29065e473c6e24935b69c85bc53daf29663c58ea6` | same | novel local +1 shoulder; support distance 19 from r247/d3094 |
| `matmul_2x2x5_rank18_d141_peterson_2026_aws_disjoint_gf2.txt` | `rect/2x2x5/best.txt.side-door-0.txt` | `4352e603dd23da3d1d083c7974ff3993b0842aa0298ae23fead7c2c0c772f30b` | same | novel rank-frontier archive door; disjoint from campaign leader |
| `matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt` | `rect/3x3x4/best.txt.side-door-0.txt` | `9178983144d2394789b417cc762c184de4fa22d0b396cb1f7fb264f765faca1a` | same | novel rank-frontier archive door; disjoint from campaign leader |
| `matmul_3x4x4_rank38_d310_peterson_2026_aws_disjoint_gf2.txt` | `rect/3x4x4/best.txt.side-door-0.txt` | `eb4eae534eb751ecad724c0859042cdc5a0ca2331d4deea583793e622b792c6d` | same | novel rank-frontier archive door; disjoint from campaign leader |
