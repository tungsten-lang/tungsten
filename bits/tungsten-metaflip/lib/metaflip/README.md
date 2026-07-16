# Namespaced Metaflip runtime

This directory is the single immutable runtime root used by the public
Metaflip executable:

- `scheme.w`, `verify.w`, `compose.w`, `fleet.w`, `rect.w`, `tui.w`, and
  `paths.w` define the major subsystems.
- `fleet/`, `rect/`, and `strategies/` contain coordinator and search modules.
  `rect/cpu_pool.w` keeps one OS thread per rectangular island across campaign
  epochs; workers reread their state slot after each barrier so rebases and
  reseeds remain visible without thread churn.
- `strategies/rect_catalyst_lift2.w` and
  `strategies/macro_double_annihilation.w` retain the exact target-directed
  setup/trigger/cleanup compilers. They are bounded offline scouts, not default
  fleet lanes: their real-frontier decision screens found no useful endpoint.
- `kernels/` contains the canonical pure-Tungsten runtime workers. Generated
  Metal sources and libraries are redirected to the writable worker cache and
  must never appear here.
- `seeds/gf2/` holds the 117 exact starting, frontier, and shoulder schemes
  selected by the square and rectangular production profiles.
- `manifests/seeds.tsv` maps every operational seed to its digest and attributed
  path in the separately curated `tungsten-metaflip-results` corpus.
- `manifests/runtime-sources.tsv` records the exact Tungsten source closure.
- `SHA256SUMS` covers every file in this subtree other than itself.

These seeds are operational inputs, not a second results corpus. New fleet
discoveries belong in `~/.tungsten/metaflip/` until independently verified and
promoted to the public results repository.
