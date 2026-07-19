# Namespaced Metaflip runtime

This directory is the single immutable runtime root used by the public
Metaflip executable:

- `scheme.w`, `verify.w`, `compose.w`, `fleet.w`, `rect.w`, `tui.w`, and
  `paths.w` define the major subsystems.
- `fleet/`, `rect/`, and `strategies/` contain coordinator and search modules.
  `rect/cpu_pool.w` keeps one OS thread per rectangular island across campaign
  epochs; workers reread their state slot after each barrier so rebases and
  reseeds remain visible without thread churn.
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

The active beam-far and affine-code frontier slots are d3096 presentations
harvested by the CUDA relay at Runpod epochs 1849 and 3306. Each is a
three-term exchange at distance six from its retained d3098 provenance parent
and saves two density bits. The two children have disjoint term supports, so
the strict density improvements preserve their two independent basins.
The independently exact d3492 c013 descendant is packaged through
`ffp_experimental_seed_paths(7)` only: c013 remains active, and the descendant
does not automatically consume a CPU frontier slot before a continuation A/B.

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
